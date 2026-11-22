{
  description = "patched llama.cpp MaxQ inference engine (RouteCrack 2.0, Quantized Split-KV, HARP-Cache v2)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Base engine, pinned to the exact commit asserted by LLAMA_COMMIT in
    # scripts/build_zen5_llama.sh. patches/llama-modchip-v3.2.patch applies on top.
    llama-cpp = {
      url = "github:ggml-org/llama.cpp/46eb1742db6d2caec1bfa848c5702b1bdcc815e5";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    llama-cpp,
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];

    forAllSystems = f:
      nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

    # TODO:keep in sync with LLAMA_BUILD_NUM in scripts/build_zen5_llama.sh.
    buildNumber = "12604";

    package = {
      lib,
      stdenv,
      cmake,
      pkg-config,
      openssl,
      # x86-64 ISA target, mirroring the PORTABLE_X86_ISA branches of
      # scripts/build_zen5_llama.sh.
      avx512 ? false,
    }: let
      isX86 = stdenv.hostPlatform.isx86_64;
      march =
        if avx512
        then "-march=skylake-avx512 -mavx512vbmi -mavx512vnni"
        else "-march=haswell -mno-avx512f";
    in
      stdenv.mkDerivation {
        pname = "llama-modchip";
        version = "3.2.0";

        src = llama-cpp;
        patches = [./patches/llama-modchip-v3.2.patch];

        nativeBuildInputs = [cmake pkg-config];

        buildInputs = [openssl];

        cmakeFlags =
          [
            (lib.cmakeFeature "LLAMA_BUILD_NUMBER" buildNumber)
            # Must stay off: GGML_NATIVE=ON bakes the builder's CPU into the output.
            (lib.cmakeBool "GGML_NATIVE" false)
            (lib.cmakeBool "GGML_OPENMP" true)
            (lib.cmakeBool "BUILD_SHARED_LIBS" true)
            (lib.cmakeBool "LLAMA_BUILD_EXAMPLES" false)
            (lib.cmakeBool "LLAMA_BUILD_TESTS" false)
            # Enables `llama-cli -hf <user>/<repo>:<quant>`.
            (lib.cmakeBool "LLAMA_OPENSSL" true)
            (lib.cmakeBool "LLAMA_CURL" false)
            (lib.cmakeBool "GGML_CUDA" false)
            (lib.cmakeBool "GGML_VULKAN" false)
            (lib.cmakeBool "GGML_BLAS" false)
          ]
          ++ lib.optionals isX86 [
            (lib.cmakeBool "GGML_AVX2" true)
            (lib.cmakeBool "GGML_FMA" true)
            (lib.cmakeBool "GGML_F16C" true)
            (lib.cmakeBool "GGML_BMI2" true)
            (lib.cmakeBool "GGML_AVX512" avx512)
            (lib.cmakeBool "GGML_AVX512_VBMI" avx512)
            (lib.cmakeBool "GGML_AVX512_VNNI" avx512)
            (lib.cmakeBool "GGML_AVX512_BF16" false)
            (lib.cmakeBool "GGML_AVX_VNNI" false)
          ];

        env = lib.optionalAttrs isX86 {NIX_CFLAGS_COMPILE = march;};

        meta = {
          description = "Patched llama.cpp MaxQ inference engine for 16/32/64 GB CPU-only hosts";
          homepage = "https://github.com/synchopate/llama-modchip";
          license = lib.licenses.asl20;
          platforms = systems;
          mainProgram = "llama-server";
        };
      };
  in {
    packages = forAllSystems (pkgs: rec {
      llama-modchip = pkgs.callPackage package {};
      default = llama-modchip;
    });

    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        packages = [
          pkgs.cmake
          pkgs.pkg-config
          pkgs.git
          pkgs.curl
          (pkgs.python3.withPackages (py: [py.numpy py.torch]))
        ];
      };
    });
  };
}
