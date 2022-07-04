# https://github.com/graalvm/labs-openjdk-19/blob/master/doc/testing.md
local run_test_spec = "test/hotspot/jtreg/compiler/jvmci";

local labsjdk_builder_version = "1c001b9a3961abc6fbc209ab926bbe9b5e96ef21";

{
    overlay: "59a8ce23e959dfb9d158db144ccb2d065e73f1e3",
    specVersion: "3",

    mxDependencies:: {
        python_version: "3",
        packages+: {
            mx: "6.1.5",
            python3: "==3.8.10",
            'pip:pylint': '==2.4.4',
      },
    },

    OSBase:: self.mxDependencies + {
        path(unixpath):: unixpath,
        exe(unixpath):: unixpath,
        jdk_home(java_home):: self.path(java_home),
        java_home(jdk_home):: self.path(jdk_home),
        copydir(src, dst):: ["cp", "-r", src, dst],
        environment+: {
            JIB_PATH: "${PATH}",
            MAKE : "make",
            ZLIB_BUNDLING: "system",
            MX_PYTHON: "python3.8"
        },
    },

    Windows:: self.OSBase + {
        path(unixpath):: std.strReplace(unixpath, "/", "\\"),
        exe(unixpath):: self.path(unixpath) + ".exe",
        # https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/xcopy
        copydir(src, dst):: ["xcopy", self.path(src), self.path(dst), "/e", "/i", "/q"],

        downloads+: {
            CYGWIN: {name: "cygwin", version: "3.0.7", platformspecific: true},
        },
        packages+: {
            # devkit_platform_revisions in make/conf/jib-profiles.js
            "devkit:VS2022-17.1.0+1" : "==0"
        },
        capabilities+: ["windows"],
        name+: "-windows-cygwin",
        os:: "windows",
        environment+: {
            JIB_PATH: "$CYGWIN\\bin;$PATH",
            ZLIB_BUNDLING: "bundled"
        },
    },
    Linux:: self.OSBase + {
        capabilities+: ["linux"],
        name+: "-linux",
        os:: "linux",
    },
    LinuxDockerAMD64Musl(defs):: self.Linux {
        docker: {
            image: defs.linux_docker_image_amd64_musl
        },
        # No packages are need for building the musl static libs
        packages: {},
    },

    LinuxAMD64(defs, for_jdk_build):: self.Linux + self.AMD64 {
        docker: {
            image: defs.linux_docker_image_amd64,
            mount_modules: true # needed for installing the devtoolset package below
        },
        packages+: if for_jdk_build then {
            # devkit_platform_revisions in make/conf/jib-profiles.js
            "devkit:gcc11.2.0-OL6.4+1" : "==0"
        } else {
            # When building/testing GraalVM, do not use a devkit as it is known not to
            # work well when dynamically linking libstdc++.
            devtoolset: "==7"
        },
    },
    LinuxAArch64(for_jdk_build):: self.Linux + self.AArch64 {
        packages+: if for_jdk_build then {
            # devkit_platform_revisions in make/conf/jib-profiles.js
            "devkit:gcc11.2.0-OL7.6+1" : "==0"
        } else {
            # See GR-26071 as well as comment in self.LinuxAMD64
            devtoolset: "==7"
        },
    },
    Darwin:: self.OSBase + {
        jdk_home(java_home):: java_home + "/../..",
        java_home(jdk_home):: jdk_home + "/Contents/Home",
        packages+: {
            # No need to specify a "make" package as Mac OS X has make 3.81
            # available once Xcode has been installed.
        },
        os:: "darwin",
        name+: "-darwin",
    },
    DarwinAMD64:: self.Darwin + self.AMD64 + {
        # JDK 17 switched to Xcode 12.4 which requires 10.15.4
        # at a minimum (GR-32439)
        capabilities+: ["darwin_catalina_7"]
    },
    DarwinAArch64:: self.Darwin + self.AArch64 + {
        capabilities+: ["darwin"],
    },

    AMD64:: {
        capabilities+: ["amd64"],
        name+: "-amd64",
    },

    AMD64Musl:: self.AMD64 + {
        name+: "-musl",
    },

    AArch64:: {
        capabilities+: ["aarch64"],
        name+: "-aarch64",
    },

    Eclipse:: {
        downloads+: {
            ECLIPSE: {
                name: "eclipse",
                version: "4.14.0",
                platformspecific: true
            }
        },
        environment+: {
            ECLIPSE_EXE: "$ECLIPSE/eclipse"
        },
    },

    JDT:: {
        downloads+: {
            JDT: {
                name: "ecj",
                version: "4.14.0",
                platformspecific: false
            }
        }
    },

    BootJDK:: {
        downloads+: {
            BOOT_JDK: {
                name : "jpg-jdk",
                version : "19",
                build_id: "26",
                release: true,
                platformspecific: true
            }
        }
    },

    MuslBootJDK:: {
        downloads+: {
            BOOT_JDK: {
                name: "oraclejdk",
                version: "19+9-musl",
                platformspecific: true,
            }
        },
        environment+: {
            LD_LIBRARY_PATH: "$BOOT_JDK/lib/server"
        }
    },

    JTReg:: {
        downloads+: {
            JT_HOME: {
                name : "jtreg",
                version : "4.2"
            }
        }
    },

    local setupJDKSources(conf) = {
        run+: [
            # To reduce load, the CI system does not fetch all tags so it must
            # be done explicitly as `build_labsjdk.py` relies on it.
            ["git", "fetch", "-q", "--tags"]
        ] + (if conf.os == "windows" then [
            # Need to fix line endings on Windows to satisfy cygwin
            # https://stackoverflow.com/a/26408129
            ["set-export", "JDK_SRC_DIR", "${PWD}\\..\\jdk"],
            ["git", "clone", "--quiet", "--config", "core.autocrlf=input", "-c", "gc.auto=0", ".", "${JDK_SRC_DIR}"]
        ] else [
            ["set-export", "JDK_SRC_DIR", "${PWD}"]
        ]) + [
            ["set-export", "JDK_SUITE_DIR", "${JDK_SRC_DIR}"]
        ],
    },

    Build(defs, conf, is_musl_build):: conf + setupJDKSources(conf) + (if is_musl_build then self.MuslBootJDK else self.BootJDK) + {
        name: "build-jdk" + conf.name,
        timelimit: "2:10:00", # Windows is the long pole
        diskspace_required: "10G",
        logs: ["*.log"],
        targets: ["gate"],

        local build_labsjdk(jdk_debug_level, java_home_env_var) = [
            ["set-export", java_home_env_var, conf.path("${PWD}/../%s-java-home" % jdk_debug_level)],
            ["python3", "-u", conf.path("${LABSJDK_BUILDER_DIR}/build_labsjdk.py"),
                "--boot-jdk=${BOOT_JDK}",
                "--clean-after-build",
                "--jdk-debug-level=" + jdk_debug_level,
                "--test=" + run_test_spec,
                "--java-home-link-target=${%s}" % java_home_env_var,
            ] + (if is_musl_build then ["--bundles=static-libs"] else [])
            + ["${JDK_SRC_DIR}"],
            (if !is_musl_build then [conf.exe("${%s}/bin/java" % java_home_env_var), "-version"] else ["echo"])
        ],

        run+: (if !is_musl_build then [
            # Checks that each devkit mentioned in this file corresponds to a devkit in make/conf/jib-profiles.js
            ["python3", "-u", conf.path("${PWD}/.ci/check_devkit_versions.py")],

            # Run some basic mx based sanity checks. This is mostly to ensure
            # IDE support does not regress.
            ["set-export", "JAVA_HOME", "${BOOT_JDK}"],
            (if std.endsWith(conf.name, 'darwin-aarch64') then ['echo', 'no checkstyle available on darwin-aarch64'] else ["mx", "-p", "${JDK_SUITE_DIR}", "checkstyle"]),
            ["mx", "-p", "${JDK_SUITE_DIR}", "eclipseinit"],
            ["mx", "-p", "${JDK_SUITE_DIR}", "canonicalizeprojects"],
        ] else []) + [
            ["set-export", "LABSJDK_BUILDER_DIR", conf.path("${PWD}/../labsjdk-builder")],
            ["git", "clone", "--quiet", "--config", "core.autocrlf=input", defs.labsjdk_builder_url, "${LABSJDK_BUILDER_DIR}"],
            ["git", "-C", "${LABSJDK_BUILDER_DIR}", "checkout", labsjdk_builder_version],

            # This restricts cygwin to be on the PATH only while using jib.
            # It must not be on the PATH when building Graal.
            ["set-export", "OLD_PATH", "${PATH}"],
            ["set-export", "PATH", "${JIB_PATH}"],
            ["set-export", "JIB_SERVER", defs.jib_server],
            ["set-export", "JIB_SERVER_MIRRORS", defs.jib_server_mirrors],
            ["set-export", "JIB_DATA_DIR", conf.path("${PWD}/../jib")]
        ] +
        build_labsjdk("release", "JAVA_HOME") +
        build_labsjdk("fastdebug", "JAVA_HOME_FASTDEBUG") +
        [
            ["set-export", "PATH", "${OLD_PATH}"],

            # Prepare for publishing
            ["set-export", "JDK_HOME", conf.path("${PWD}/jdk_home")],
            ["cd", "${JAVA_HOME}"],
            conf.copydir(conf.jdk_home("."), "${JDK_HOME}")
        ],

        publishArtifacts+: if !is_musl_build then [
            {
                name: "labsjdk" + conf.name,
                dir: ".",
                patterns: ["jdk_home"]
            }
        ] else [
            # In contrast to the labsjdk-builder repo, the gate in this repo
            # does not bundle the musl static library into the main JDK. That is
            # why the musl static library builder does not publish anything.
            # The musl-based builder in this repo exists solely to ensure
            # the musl build does not regress.
        ],
    },

    # Downstream Graal branch to test against.
    local downstream_branch = "master",

    local clone_graal = {
        run+: [
            ["git", "clone", ["mx", "urlrewrite", "https://github.com/graalvm/graal.git"]],

            # This puts cygwin on the PATH so that `test` and `cat` are available
            ["set-export", "OLD_PATH", "${PATH}"],
            ["set-export", "PATH", "${JIB_PATH}"],

            # Use branch recorded by previous builder or record it now for subsequent builder(s)
            ["test", "-f", "graal.commit", "||", "echo", downstream_branch, ">graal.commit"],
            ["git", "-C", "graal", "checkout", ["cat", "graal.commit"], "||", "true"],
            ["git", "-C", "graal", "rev-list", "-n", "1", "HEAD", ">graal.commit"],

            # Restore PATH as cygwin must not be on the PATH when building Graal.
            ["set-export", "PATH", "${OLD_PATH}"]
        ]
    },

    local requireLabsJDK(conf) = {
        requireArtifacts+: [
            {
                name: "labsjdk" + conf.name,
                dir: "."
            }
        ],
        run+: [
            ["set-export", "JAVA_HOME", conf.java_home("${PWD}/jdk_home")]
        ]
    },

    CompilerTests(conf):: conf + requireLabsJDK(conf) + clone_graal + {
        name: "test-compiler" + conf.name,
        timelimit: "1:00:00",
        logs: ["*.log"],
        targets: ["gate"],
        run+: [
            ["mx", "-p", "graal/compiler", "gate", "--tags", "build,test,bootstraplite",
             /* GR-39558 */ "--extra-unittest-argument=Copy"]
        ]
    },

    # Build and test JavaScript on GraalVM
    JavaScriptTests(conf):: conf + requireLabsJDK(conf) + clone_graal + {
        local jsvm = ["mx", "-p", "graal/vm",
            "--dynamicimports", "/graal-js,/substratevm",
            "--components=Graal.js,Native Image",
            "--native-images=js"],

        name: "test-js" + conf.name,
        timelimit: "1:00:00",
        logs: ["*.log"],
        targets: ["gate"],
        run+: [
            # Build and test JavaScript on GraalVM
            jsvm + ["build"],
            ["set-export", "GRAALVM_HOME", jsvm + ["graalvm-home"]],
            ["${GRAALVM_HOME}/bin/js", ".ci/add.js"],
        ] +
        if conf.os != "windows" then [
            # Native launchers do not yet support --jvm mode on Windows
            ["${GRAALVM_HOME}/bin/js", "--jvm", ".ci/add.js"]
        ] else []
    },

    # Build LibGraal
    BuildLibGraal(conf):: conf + requireLabsJDK(conf) + clone_graal + {
        name: "build-libgraal" + conf.name,
        timelimit: "1:30:00",
        logs: ["*.log"],
        targets: ["gate"],
        publishArtifacts: [
            {
                name: "libgraal" + conf.name + ".graal.commit",
                dir: ".",
                patterns: ["graal.commit"]
            },
            {
                name: "libgraal" + conf.name,
                dir: ".",
                patterns: ["graal/*/mxbuild"]
            }
        ],
        run+: [
            ["mx", "-p", "graal/vm", "--env", "libgraal",
                "--extra-image-builder-argument=-J-esa",
                "--extra-image-builder-argument=-H:+ReportExceptionStackTraces", "build"],
        ]
    },

    local requireLibGraal(conf) = {
        requireArtifacts+: [
            {
                name: "libgraal" + conf.name + ".graal.commit",
                dir: ".",
                autoExtract: true
            },
            {
                name: "libgraal" + conf.name,
                dir: ".",
                autoExtract: false
            }
        ],
    },

    # Test LibGraal
    TestLibGraal(conf):: conf + requireLabsJDK(conf) + clone_graal + requireLibGraal(conf) {
        name: "test-libgraal" + conf.name,
        timelimit: "1:30:00",
        logs: ["*.log"],
        targets: ["gate"],
        run+: [
            ["unpack-artifact", "libgraal" + conf.name],
            ["mx", "-p", "graal/vm",
                "--env", "libgraal",
                "gate", "--task", "LibGraal"],
        ],
        environment+: {
            # The Truffle TCK tests run as a part of Truffle TCK gate
            TEST_LIBGRAAL_EXCLUDE: "com.oracle.truffle.tck.tests.* com.oracle.truffle.tools.*"
        }
    },

    # Map between CI os+arch and mach5 execution platforms (see closed/task-definitions/execution-platforms.js).
    # All the execution platforms described by the `supportedPlatforms` variable in
    # closed/task-definitions/jobs/graalvm-jck.js must be listed here.
    Mach5ExecutionPlatforms:: {
        linux_amd64: { os: "linux", arch: "amd64", name: "linux-x64-OL-7" },
        darwin_amd64: { os: "darwin", arch: "amd64", name: "macosx-x64-10.13" },
        windows_amd64: { os: "windows", arch: "amd64", name: "windows-x64" },
    },

    local build_confs(defs) = [
        self.LinuxAMD64(defs, true),
        self.LinuxAArch64(true),
        self.DarwinAMD64,
        self.DarwinAArch64,
        self.Windows + self.AMD64
    ],

    local graal_confs(defs) = [
        self.LinuxAMD64(defs, false),
        self.LinuxAArch64(false),
        self.DarwinAMD64,
        self.DarwinAArch64,
        self.Windows + self.AMD64
    ],

    local amd64_musl_confs(defs) = [
        self.LinuxDockerAMD64Musl(defs) + self.AMD64Musl,
    ],

    DefineBuilds(defs):: [ self.Build(defs, conf, is_musl_build=false) for conf in build_confs(defs) ] +
            [ self.CompilerTests(conf) for conf in graal_confs(defs) ] +

            # GR-39560 [ self.JavaScriptTests(conf) for conf in graal_confs ] +

            # GR-39559 [ self.BuildLibGraal(conf) for conf in graal_confs ] +
            # GR-39559 [ self.TestLibGraal(conf) for conf in graal_confs ] +

            [ self.Build(defs, conf, is_musl_build=true) for conf in amd64_musl_confs(defs) ],
            
    local defs = {
        labsjdk_builder_url: "<placeholder",
        linux_docker_image_amd64_musl: "<placeholder",
        linux_docker_image_amd64: "<placeholder",
        jib_server: "<placeholder",
        jib_server_mirrors: "<placeholder"
    },
    
    builds: self.DefineBuilds(defs)
}
