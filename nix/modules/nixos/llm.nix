# Local LLM inference
{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

let
  unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };

  llamaCpp = unstable.pkgsForCudaArch.sm_86.llama-cpp;
  llamaServer = lib.getExe' llamaCpp "llama-server";
  modelsDir = "/var/lib/llm-models";
  bothCards = [ "CUDA_DEVICE_ORDER=PCI_BUS_ID" ];
  splitFlags = [
    "-sm layer"
    "-ts 1/1"
  ];

  kvF16 = [
    "--cache-type-k f16"
    "--cache-type-v f16"
  ];
  kvQ8 = [
    "--cache-type-k q8_0"
    "--cache-type-v q8_0"
  ];

  serverFlags = [
    "--parallel 1"
    "--jinja"
    "-b 4096"
    "-ub 1024"
    "--no-webui"
  ];

  qwenSampling = [
    "--temp 0.7"
    "--top-p 0.80"
    "--top-k 20"
    "--presence-penalty 1.5"
  ];

  glmSampling = [
    "--temp 0.7"
    "--top-p 1.0"
    "--repeat-penalty 1.0"
  ];

  # llama-swap runs one of these at a time, so each is sized to the whole card
  # pair rather than to a share of it.
  mkModel =
    {
      model,
      ctx,
      kv ? kvF16,
      sampling,
    }:
    {
      env = bothCards;
      cmd = lib.concatStringsSep " " (
        [
          llamaServer
          "--model ${modelsDir}/${model}"
          "--port \${PORT}"
          "--host 127.0.0.1"
          "-c ${toString ctx}"
          "-fa on"
        ]
        ++ splitFlags
        ++ kv
        ++ serverFlags
        ++ sampling
      );
    };
in
{
  services.llama-swap = {
    enable = true;
    package = unstable.llama-swap;
    port = 8090;
    listenAddress = "127.0.0.1";

    settings = {
      models = {
        "qwen3.8-27b" = mkModel {
          model = "qwen3.8-27b/Qwen3.8-27B-UD-Q4_K_XL.gguf";
          ctx = 262144;
          sampling = qwenSampling;
        };

        # Refusal-ablated builds; upstream huihui-ai/Huihui-Qwen3.8-27B-abliterated-GGUF.
        # The stock Q6/Q8 GGUFs are still under qwen3.8-27b-q6/ and qwen3.8-27b-q8/
        # if these ever need to be swapped back.
        "qwen3.8-27b-uncensored-q6" = mkModel {
          model = "qwen3.8-27b-uncensored-q6/Huihui-Qwen3.8-27B-abliterated-UD-Q6_K_XL.gguf";
          ctx = 262144;
          sampling = qwenSampling;
        };

        "qwen3.8-27b-uncensored-q8" = mkModel {
          model = "qwen3.8-27b-uncensored-q8/Huihui-Qwen3.8-27B-abliterated-UD-Q8_K_XL.gguf";
          ctx = 262144;
          kv = kvQ8;
          sampling = qwenSampling;
        };

        "glm-4.7-flash" = mkModel {
          model = "glm-4.7-flash/GLM-4.7-Flash-UD-Q4_K_XL.gguf";
          ctx = 202752;
          sampling = glmSampling;
        };
      };
    };
  };

  # Manual start
  systemd.services.llama-swap = {
    wantedBy = lib.mkForce [ ];
    serviceConfig = {
      MemoryDenyWriteExecute = lib.mkForce false;
      ReadOnlyPaths = [ modelsDir ];
      # Without this the JIT cache lands somewhere DynamicUser cannot write
      Environment = [ "CUDA_CACHE_PATH=/var/cache/llm/cuda" ];
      CacheDirectory = "llm";
    };
  };

  systemd.tmpfiles.rules = [
    "d ${modelsDir} 0755 dennis users -"
    "h ${modelsDir} - - - - +C"
  ];

  environment.systemPackages = [
    llamaCpp
    unstable.aider-chat
    pkgs.python3Packages.huggingface-hub
    pkgs.python3
  ];
}
