# Egress allowlist for the sandbox
# https://docs.github.com/en/copilot/reference/copilot-allowlist-reference
{
  certificates = [
    "crl3.digicert.com"
    "crl4.digicert.com"
    "ocsp.digicert.com"
    "ts-crl.ws.symantec.com"
    "ts-ocsp.ws.symantec.com"
    "s.symcb.com"
    "s.symcd.com"
    "crl.geotrust.com"
    "ocsp.geotrust.com"
    "crl.thawte.com"
    "ocsp.thawte.com"
    "crl.verisign.com"
    "ocsp.verisign.com"
    "crl.globalsign.com"
    "ocsp.globalsign.com"
    "crls.ssl.com"
    "ocsp.ssl.com"
    "crl.identrust.com"
    "ocsp.identrust.com"
    "crl.sectigo.com"
    "ocsp.sectigo.com"
    "crl.usertrust.com"
    "ocsp.usertrust.com"
    "oneocsp.microsoft.com"
  ];

  github = [
    "github.com"
    "api.github.com"
    "githubusercontent.com"
    "raw.githubusercontent.com"
    "objects.githubusercontent.com"
    "github-cloud.githubusercontent.com"
    "github-cloud.s3.amazonaws.com"
    "codeload.github.com"
    "lfs.github.com"
    "uploads.github.com"
    "scanning-api.github.com"
    "api.mcp.github.com"
    "gitlab.com"
  ];

  containers = [
    "ghcr.io"
    "registry.hub.docker.com"
    "docker.io"
    "docker.com"
    "auth.docker.io"
    "production.cloudflare.docker.com"
    "quay.io"
    "mcr.microsoft.com"
    "gcr.io"
    "public.ecr.aws"
  ];

  javascript = [
    "npmjs.org"
    "npmjs.com"
    "registry.npmjs.org"
    "registry.npmjs.com"
    "skimdb.npmjs.com"
    "npm.pkg.github.com"
    "api.npms.io"
    "nodejs.org"
    "yarnpkg.com"
    "registry.yarnpkg.com"
    "repo.yarnpkg.com"
    "deb.nodesource.com"
    "get.pnpm.io"
    "bun.sh"
    "deno.land"
    "registry.bower.io"
    "binaries.prisma.sh"
  ];

  python = [
    "pypi.org"
    "pypi.python.org"
    "pip.pypa.io"
    "pythonhosted.org"
    "files.pythonhosted.org"
    "bootstrap.pypa.io"
    "conda.binstar.org"
    "conda.anaconda.org"
    "binstar.org"
    "anaconda.org"
    "repo.anaconda.com"
    "repo.continuum.io"
    "download.pytorch.org"
  ];

  rust = [
    "crates.io"
    "index.crates.io"
    "static.crates.io"
    "sh.rustup.rs"
    "static.rust-lang.org"
  ];

  go = [
    "go.dev"
    "golang.org"
    "proxy.golang.org"
    "sum.golang.org"
    "pkg.go.dev"
    "goproxy.io"
  ];

  java = [
    "www.java.com"
    "jdk.java.net"
    "api.adoptium.net"
    "adoptium.net"
    "search.maven.org"
    "maven.apache.org"
    "repo.maven.apache.org"
    "repo1.maven.org"
    "maven.pkg.github.com"
    "maven-central.storage-download.googleapis.com"
    "maven.google.com"
    "maven.oracle.com"
    "oss.sonatype.org"
    "repo.spring.io"
    "gradle.org"
    "services.gradle.org"
    "plugins.gradle.org"
    "plugins-artifacts.gradle.org"
    "repo.grails.org"
    "download.eclipse.org"
    "download.oracle.com"
  ];

  dotnet = [
    "nuget.org"
    "api.nuget.org"
    "dist.nuget.org"
    "nuget.pkg.github.com"
    "azuresearch-usnc.nuget.org"
    "azuresearch-ussc.nuget.org"
    "nugetregistryv2prod.blob.core.windows.net"
    "dotnet.microsoft.com"
    "builds.dotnet.microsoft.com"
    "dotnetcli.blob.core.windows.net"
    "dotnetcli.azureedge.net"
    "download.visualstudio.microsoft.com"
    "pkgs.dev.azure.com"
    "dc.services.visualstudio.com"
    "dot.net"
    "ci.dot.net"
    "www.microsoft.com"
  ];

  ruby = [
    "rubygems.org"
    "api.rubygems.org"
    "index.rubygems.org"
    "bundler.rubygems.org"
    "rubygems.pkg.github.com"
    "gems.rubyforge.org"
    "gems.rubyonrails.org"
    "cache.ruby-lang.org"
    "rvm.io"
  ];

  php = [
    "packagist.org"
    "repo.packagist.org"
    "getcomposer.org"
  ];

  perl = [
    "cpan.org"
    "www.cpan.org"
    "metacpan.org"
    "cpan.metacpan.org"
  ];

  haskell = [
    "haskell.org"
    "hackage.haskell.org"
    "get-ghcup.haskell.org"
    "downloads.haskell.org"
  ];

  dart = [
    "pub.dev"
    "pub.dartlang.org"
  ];

  swift = [
    "swift.org"
    "download.swift.org"
    "cocoapods.org"
    "cdn.cocoapods.org"
  ];

  linux = [
    "archive.ubuntu.com"
    "security.ubuntu.com"
    "azure.archive.ubuntu.com"
    "ppa.launchpad.net"
    "keyserver.ubuntu.com"
    "api.snapcraft.io"
    "deb.debian.org"
    "security.debian.org"
    "keyring.debian.org"
    "packages.debian.org"
    "debian.map.fastlydns.net"
    "apt.llvm.org"
    "dl.fedoraproject.org"
    "mirrors.fedoraproject.org"
    "download.fedoraproject.org"
    "mirror.centos.org"
    "vault.centos.org"
    "dl-cdn.alpinelinux.org"
    "pkg.alpinelinux.org"
    "mirror.archlinux.org"
    "archlinux.org"
    "download.opensuse.org"
    "cdn.redhat.com"
    "packagecloud.io"
    "packages.cloud.google.com"
    "packages.microsoft.com"
  ];

  tooling = [
    "releases.hashicorp.com"
    "apt.releases.hashicorp.com"
    "yum.releases.hashicorp.com"
    "registry.terraform.io"
    "json-schema.org"
    "json.schemastore.org"
    "cdn.playwright.dev"
    "playwright.download.prss.microsoft.com"
    "playwright.azureedge.net"
    "dl.k8s.io"
    "pkgs.k8s.io"
  ];

  opencode = [
    "models.dev"
    "opencode.ai"
  ];

  nix = [
    "cache.nixos.org"
    "channels.nixos.org"
    "nixos.org"
    "cache.nixos-cuda.org"
  ];
}
