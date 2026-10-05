// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.ComponentModel;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using Microsoft.ML.Tokenizers;
using Touki;

namespace SkillEvaluation.Onnx;

/// <summary>
///  Owns maintained exact tokenization and lazy, explicit single-threaded CPU inference for one pinned NLI profile.
/// </summary>
public sealed class CpuNliBackend : DisposableBase, IGroundingBackend
{
    private readonly VerifiedGroundingAssets _assets;
    private readonly SentencePieceTokenizer _tokenizer;
    private InferenceSession? _session;
    private bool _disposed;

    /// <summary>
    ///  Gets the actual adapter, dependency-binary, and managed-runtime identity.
    /// </summary>
    public GroundingBackendIdentity Identity { get; }

    /// <summary>
    ///  Verifies the supported profile and loads its tokenizer without opening an inference session.
    /// </summary>
    /// <param name="assets">The strict locally verified asset closure.</param>
    public CpuNliBackend(VerifiedGroundingAssets assets)
    {
        ArgumentNullException.ThrowIfNull(assets);
        PinnedNliProfile.RequireSupported(assets);
        GroundingAssets.RequireUnchanged(assets);
        string? tokenizerPackageVersion = typeof(SentencePieceTokenizer).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;

        PinnedNliProfile.RequireTokenizerPackageVersion(
            tokenizerPackageVersion, assets.Manifest.RuntimeVersions.Tokenizers);

        _assets = assets;
        using FileStream model = File.OpenRead(assets.Paths["sentencepiece"]);
        _tokenizer = SentencePieceTokenizer.Create(
            model, addBeginningOfSentence: false, addEndOfSentence: false,
            specialTokens: new Dictionary<string, int>(StringComparer.Ordinal)
            {
                ["[PAD]"] = 0,
                ["[CLS]"] = 1,
                ["[SEP]"] = 2,
                ["[UNK]"] = 3,
                ["[MASK]"] = 128000
            });

        string nativeVersion;
        object[] nativeFiles;
        try
        {
            nativeVersion = OrtEnv.Instance().GetVersionString();
            if (nativeVersion != assets.Manifest.RuntimeVersions.OnnxRuntime)
            {
                throw new EvaluationContractException("The loaded native runtime differs from the pinned version.");
            }

            using Process process = Process.GetCurrentProcess();
            nativeFiles = process.Modules.Cast<ProcessModule>()
                .Where(value => value.ModuleName.StartsWith("onnxruntime", StringComparison.OrdinalIgnoreCase)
                    || value.ModuleName.StartsWith("libonnxruntime", StringComparison.OrdinalIgnoreCase))
                .OrderBy(value => value.ModuleName, StringComparer.Ordinal)
                .Select(value => new
                {
                    name = value.ModuleName,
                    sha256 = ContractJson.HashFile(value.FileName)
                }).ToArray();

            if (nativeFiles.Length == 0)
            {
                throw new EvaluationContractException("The loaded native runtime binary identity is unavailable.");
            }
        }
        catch (Exception error) when (error is OnnxRuntimeException or Win32Exception or NotSupportedException
            || NativeLibraryFailures.FindCause(error) is not null)
        {
            Exception cause = NativeLibraryFailures.FindCause(error) ?? error;
            throw new EvaluationContractException($"CPU grounding runtime initialization failed: {cause.Message}");
        }

        string revision = ContractJson.Revision(new
        {
            adapter = "deberta-nli-cpu/v1",
            implementation = ContractJson.HashFile(typeof(CpuNliBackend).Assembly.Location),
            runtime = ContractJson.HashFile(typeof(InferenceSession).Assembly.Location),
            tokenizer = ContractJson.HashFile(typeof(SentencePieceTokenizer).Assembly.Location),
            tokenizerPackageVersion,
            nativeVersion,
            nativeFiles,
            framework = RuntimeInformation.FrameworkDescription,
            platform = RuntimeInformation.OSDescription,
            architecture = RuntimeInformation.ProcessArchitecture.ToString(),
            options = "cpu/sequential/intra-1/inter-1/float32/complete-pair/no-truncation"
        });

        Identity = new("onnx-cpu-deberta-nli", Synthetic: false, revision,
            $"native {nativeVersion}; {typeof(InferenceSession).Assembly.GetName().FullName}; {RuntimeInformation.FrameworkDescription}",
            typeof(SentencePieceTokenizer).Assembly.GetName().FullName
                ?? throw new EvaluationContractException("Tokenizer assembly identity is unavailable."));
    }

    /// <summary>
    ///  Uses maintained SentencePiece segmentation and explicit DeBERTa pair specials without inference.
    /// </summary>
    /// <param name="premise">The complete supplied premise text.</param>
    /// <param name="claim">The exact nonempty artifact claim.</param>
    /// <returns>The complete pair tensors, rejected rather than truncated if overlength.</returns>
    public GroundingTokens Encode(string premise, string claim)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (string.IsNullOrWhiteSpace(premise) || string.IsNullOrWhiteSpace(claim))
        {
            throw new EvaluationContractException("Grounding premise and claim must both contain text.");
        }

        int[] first = _tokenizer.EncodeToIds(
            premise, addBeginningOfSentence: false, addEndOfSentence: false).ToArray();

        int[] second = _tokenizer.EncodeToIds(
            claim, addBeginningOfSentence: false, addEndOfSentence: false).ToArray();

        return DebertaPairEncoding.Compose(first, second, _assets.Manifest.MaximumTokens);
    }

    /// <summary>
    ///  Lazily opens the pinned CPU graph and explicitly dispatches one already validated pair.
    /// </summary>
    /// <param name="tokens">The complete canonical pair tensors.</param>
    /// <returns>The untouched finite contradiction/entailment/neutral logits.</returns>
    public GroundingLogits Predict(GroundingTokens tokens)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        GroundingInference.ValidateTokens(tokens, _assets.Manifest.MaximumTokens);
        try
        {
            _session ??= OpenSession();
            int count = tokens.InputIds.Length;
            NamedOnnxValue[] input =
            [
                NamedOnnxValue.CreateFromTensor("input_ids",
                    new DenseTensor<long>(tokens.InputIds.Select(value => (long)value).ToArray(), [1, count])),
                NamedOnnxValue.CreateFromTensor("attention_mask",
                    new DenseTensor<long>(tokens.AttentionMask.Select(value => (long)value).ToArray(), [1, count]))
            ];

            using IDisposableReadOnlyCollection<DisposableNamedOnnxValue> output = _session.Run(input);
            float[] scores = output.Single().AsTensor<float>().ToArray();
            if (scores.Length != 3 || scores.Any(value => !float.IsFinite(value)))
            {
                throw new EvaluationContractException("The pinned NLI graph returned nonfinite or non-three-way logits.");
            }

            return new(scores[0], scores[1], scores[2]);
        }
        catch (Exception error) when (error is OnnxRuntimeException
            || NativeLibraryFailures.FindCause(error) is not null)
        {
            Exception cause = NativeLibraryFailures.FindCause(error) ?? error;
            throw new EvaluationContractException($"CPU grounding runtime failed: {cause.Message}");
        }
    }

    /// <summary>
    ///  Releases the owned native session on every explicit disposal path.
    /// </summary>
    /// <param name="disposing">Whether deterministic disposal was requested.</param>
    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _session?.Dispose();
            _session = null;
            _disposed = true;
        }
    }

    /// <summary>
    ///  Opens only CPU execution and rejects unsupported tensor metadata before accepting the graph.
    /// </summary>
    /// <returns>The owned validated single-threaded session.</returns>
    private InferenceSession OpenSession()
    {
        GroundingAssets.RequireUnchanged(_assets);
        using SessionOptions options = new()
        {
            InterOpNumThreads = 1,
            IntraOpNumThreads = 1,
            ExecutionMode = ExecutionMode.ORT_SEQUENTIAL,
            GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL
        };

        options.AppendExecutionProvider_CPU(0);
        if (OrtEnv.Instance().GetVersionString() != _assets.Manifest.RuntimeVersions.OnnxRuntime)
        {
            throw new EvaluationContractException("The loaded native runtime differs from the pinned version.");
        }

        InferenceSession session = new(_assets.Paths["model"], options);
        try
        {
            if (!session.InputNames.SequenceEqual(_assets.Manifest.InputNames)
                || session.InputMetadata.Any(value => value.Value.ElementType != typeof(long)
                    || value.Value.Dimensions.Length != 2)
                || session.OutputNames.Count != 1
                || session.OutputMetadata.Single().Value.ElementType != typeof(float)
                || session.OutputMetadata.Single().Value.Dimensions.Length != 2
                || session.OutputMetadata.Single().Value.Dimensions[1] != 3)
            {
                throw new EvaluationContractException("The pinned graph's input/output metadata is unsupported.");
            }

            GroundingAssets.RequireUnchanged(_assets);
            return session;
        }
        catch (EvaluationContractException)
        {
            session.Dispose();
            throw;
        }
    }
}
