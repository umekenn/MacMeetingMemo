#!/usr/bin/env python3
"""
Minimal .xcodeproj generator for MeetingMemo.
Generates a valid Xcode project without xcodegen.
"""
import os
import uuid

def uid():
    """Generate 24-char Xcode-style ID"""
    return uuid.uuid4().hex[:24].upper()

# ─── IDs ────────────────────────────────────────────────────────────────────
PROJECT_ID       = uid()
MAIN_GROUP_ID    = uid()
SOURCES_GROUP_ID = uid()
VIEWS_GROUP_ID   = uid()
MANAGERS_GROUP_ID= uid()
MODELS_GROUP_ID  = uid()
RESOURCES_GROUP_ID = uid()
TARGET_ID        = uid()
BUILD_PHASE_SOURCES_ID = uid()
BUILD_PHASE_FRAMEWORKS_ID = uid()
BUILD_PHASE_RESOURCES_ID = uid()
NATIVE_TARGET_SETTINGS_ID = uid()
PROJECT_SETTINGS_ID = uid()
DEBUG_CONFIG_ID  = uid()
RELEASE_CONFIG_ID = uid()
TARGET_DEBUG_CONFIG_ID  = uid()
TARGET_RELEASE_CONFIG_ID= uid()
CONFIG_LIST_PROJECT_ID = uid()
CONFIG_LIST_TARGET_ID  = uid()

# ─── Collect source files ────────────────────────────────────────────────────
WORKSPACE = os.path.dirname(os.path.abspath(__file__))

def collect_sources():
    groups = {
        "Views":    [],
        "Managers": [],
        "Models":   [],
        "Root":     [],
    }
    base = os.path.join(WORKSPACE, "Sources", "MeetingMemo")
    for root, dirs, files in os.walk(base):
        dirs.sort()
        for f in sorted(files):
            if not f.endswith(".swift"):
                continue
            rel = os.path.relpath(os.path.join(root, f), WORKSPACE)
            if "Views" in root:
                groups["Views"].append((f, rel))
            elif "Managers" in root:
                groups["Managers"].append((f, rel))
            elif "Models" in root:
                groups["Models"].append((f, rel))
            else:
                groups["Root"].append((f, rel))
    return groups

def collect_resources():
    res = []
    rdir = os.path.join(WORKSPACE, "Resources")
    for f in sorted(os.listdir(rdir)):
        rel = os.path.join("Resources", f)
        res.append((f, rel))
    return res

groups = collect_sources()
resources = collect_resources()

# Assign IDs to each file
file_ids = {}
for group_name, files in groups.items():
    for (name, path) in files:
        file_ids[path] = uid()

res_ids = {}
for (name, path) in resources:
    res_ids[path] = uid()

# Build source file entries
def pbx_file_ref(fid, name, path, source_tree="SOURCE_ROOT"):
    ext = os.path.splitext(name)[1]
    filetype = {
        ".swift": "sourcecode.swift",
        ".plist": "text.plist.xml",
        ".entitlements": "text.plist.entitlements",
        ".png": "image.png",
        ".md": "net.daringfireball.markdown",
    }.get(ext, "text")
    return f'\t\t{fid} = {{isa = PBXFileReference; lastKnownFileType = {filetype}; name = {name}; path = {path}; sourceTree = "<{source_tree}>"; }};\n'

def pbx_build_file(build_id, file_id, name):
    return f'\t\t{build_id} = {{isa = PBXBuildFile; fileRef = {file_id} /* {name} */; }};\n'

# Generate build file IDs for sources
build_ids = {}
for path, fid in file_ids.items():
    build_ids[path] = uid()

res_build_ids = {}
for (name, path) in resources:
    if path.endswith(".plist") or path.endswith(".entitlements"):
        pass  # not added to resources phase
    else:
        res_build_ids[path] = uid()

# ─── Build pbxproj content ───────────────────────────────────────────────────
lines = []
lines.append("// !$*UTF8*$!")
lines.append("{")
lines.append("\tarchiveVersion = 1;")
lines.append("\tclasses = {")
lines.append("\t};")
lines.append("\tobjectVersion = 56;")
lines.append("\tobjects = {")
lines.append("")

# PBXBuildFile section
lines.append("/* Begin PBXBuildFile section */")
for path, fid in file_ids.items():
    name = os.path.basename(path)
    bid = build_ids[path]
    lines.append(f'\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {name} */; }};')
lines.append("/* End PBXBuildFile section */")
lines.append("")

# PBXFileReference section
lines.append("/* Begin PBXFileReference section */")
for path, fid in file_ids.items():
    name = os.path.basename(path)
    ext = os.path.splitext(name)[1]
    ft = "sourcecode.swift"
    lines.append(f'\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = {name}; sourceTree = "<group>"; }};')
for (name, path) in resources:
    fid = res_ids[path]
    ext = os.path.splitext(name)[1]
    ft_map = {".plist": "text.plist.xml", ".entitlements": "text.plist.entitlements"}
    ft = ft_map.get(ext, "text")
    lines.append(f'\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = {name}; sourceTree = "<group>"; }};')

PRODUCT_ID = uid()
lines.append(f'\t\t{PRODUCT_ID} /* Meeting Memo.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "Meeting Memo.app"; sourceTree = BUILT_PRODUCTS_DIR; }};')
lines.append("/* End PBXFileReference section */")
lines.append("")

# PBXFrameworksBuildPhase
lines.append("/* Begin PBXFrameworksBuildPhase section */")
lines.append(f'\t\t{BUILD_PHASE_FRAMEWORKS_ID} /* Frameworks */ = {{')
lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXFrameworksBuildPhase section */")
lines.append("")

# PBXGroup section
lines.append("/* Begin PBXGroup section */")

# Main group
lines.append(f'\t\t{MAIN_GROUP_ID} = {{')
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append(f'\t\t\t\t{SOURCES_GROUP_ID} /* Sources */,')
lines.append(f'\t\t\t\t{RESOURCES_GROUP_ID} /* Resources */,')
lines.append("\t\t\t);")
lines.append('\t\t\tsourceTree = "<group>";')
lines.append("\t\t};")

# Sources group
lines.append(f'\t\t{SOURCES_GROUP_ID} /* Sources */ = {{')
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
for (name, path) in groups["Root"]:
    lines.append(f'\t\t\t\t{file_ids[path]} /* {name} */,')
lines.append(f'\t\t\t\t{VIEWS_GROUP_ID} /* Views */,')
lines.append(f'\t\t\t\t{MANAGERS_GROUP_ID} /* Managers */,')
lines.append(f'\t\t\t\t{MODELS_GROUP_ID} /* Models */,')
lines.append("\t\t\t);")
lines.append('\t\t\tname = Sources;')
lines.append('\t\t\tpath = "Sources/MeetingMemo";')
lines.append('\t\t\tsourceTree = "<group>";')
lines.append("\t\t};")

# Views group
lines.append(f'\t\t{VIEWS_GROUP_ID} /* Views */ = {{')
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
for (name, path) in groups["Views"]:
    lines.append(f'\t\t\t\t{file_ids[path]} /* {name} */,')
lines.append("\t\t\t);")
lines.append('\t\t\tname = Views;')
lines.append('\t\t\tpath = Views;')
lines.append('\t\t\tsourceTree = "<group>";')
lines.append("\t\t};")

# Managers group
lines.append(f'\t\t{MANAGERS_GROUP_ID} /* Managers */ = {{')
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
for (name, path) in groups["Managers"]:
    lines.append(f'\t\t\t\t{file_ids[path]} /* {name} */,')
lines.append("\t\t\t);")
lines.append('\t\t\tname = Managers;')
lines.append('\t\t\tpath = Managers;')
lines.append('\t\t\tsourceTree = "<group>";')
lines.append("\t\t};")

# Models group
lines.append(f'\t\t{MODELS_GROUP_ID} /* Models */ = {{')
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
for (name, path) in groups["Models"]:
    lines.append(f'\t\t\t\t{file_ids[path]} /* {name} */,')
lines.append("\t\t\t);")
lines.append('\t\t\tname = Models;')
lines.append('\t\t\tpath = Models;')
lines.append('\t\t\tsourceTree = "<group>";')
lines.append("\t\t};")

# Resources group
lines.append(f'\t\t{RESOURCES_GROUP_ID} /* Resources */ = {{')
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
for (name, path) in resources:
    lines.append(f'\t\t\t\t{res_ids[path]} /* {name} */,')
lines.append("\t\t\t);")
lines.append('\t\t\tname = Resources;')
lines.append('\t\t\tpath = Resources;')
lines.append('\t\t\tsourceTree = "<group>";')
lines.append("\t\t};")

lines.append("/* End PBXGroup section */")
lines.append("")

# PBXNativeTarget
lines.append("/* Begin PBXNativeTarget section */")
lines.append(f'\t\t{TARGET_ID} /* MeetingMemo */ = {{')
lines.append("\t\t\tisa = PBXNativeTarget;")
lines.append(f'\t\t\tbuildConfigurationList = {CONFIG_LIST_TARGET_ID} /* Build configuration list for PBXNativeTarget "MeetingMemo" */;')
lines.append("\t\t\tbuildPhases = (")
lines.append(f'\t\t\t\t{BUILD_PHASE_SOURCES_ID} /* Sources */,')
lines.append(f'\t\t\t\t{BUILD_PHASE_FRAMEWORKS_ID} /* Frameworks */,')
lines.append("\t\t\t);")
lines.append("\t\t\tbuildRules = (")
lines.append("\t\t\t);")
lines.append("\t\t\tdependencies = (")
lines.append("\t\t\t);")
lines.append('\t\t\tname = MeetingMemo;')
lines.append('\t\t\tproductName = "Meeting Memo";')
lines.append(f'\t\t\tproductReference = {PRODUCT_ID} /* Meeting Memo.app */;')
lines.append("\t\t\tproductType = \"com.apple.product-type.application\";")
lines.append("\t\t};")
lines.append("/* End PBXNativeTarget section */")
lines.append("")

# PBXProject
lines.append("/* Begin PBXProject section */")
lines.append(f'\t\t{PROJECT_ID} /* Project object */ = {{')
lines.append("\t\t\tisa = PBXProject;")
lines.append("\t\t\tattributes = {")
lines.append('\t\t\t\tLastUpgradeCheck = 1500;')
lines.append("\t\t\t};")
lines.append(f'\t\t\tbuildConfigurationList = {CONFIG_LIST_PROJECT_ID} /* Build configuration list for PBXProject "MeetingMemo" */;')
lines.append('\t\t\tcompatibilityVersion = "Xcode 14.0";')
lines.append('\t\t\tdevelopmentRegion = ja;')
lines.append('\t\t\thasScannedForEncodings = 0;')
lines.append('\t\t\tknownRegions = (')
lines.append('\t\t\t\ten,')
lines.append('\t\t\t\tja,')
lines.append('\t\t\t\tBase,')
lines.append('\t\t\t);')
lines.append(f'\t\t\tmainGroup = {MAIN_GROUP_ID};')
lines.append(f'\t\t\tproductRefGroup = {MAIN_GROUP_ID};')
lines.append('\t\t\tprojectDirPath = "";')
lines.append('\t\t\tprojectRoot = "";')
lines.append('\t\t\ttargets = (')
lines.append(f'\t\t\t\t{TARGET_ID} /* MeetingMemo */,')
lines.append('\t\t\t);')
lines.append('\t\t};')
lines.append("/* End PBXProject section */")
lines.append("")

# PBXSourcesBuildPhase
lines.append("/* Begin PBXSourcesBuildPhase section */")
lines.append(f'\t\t{BUILD_PHASE_SOURCES_ID} /* Sources */ = {{')
lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
for path, bid in build_ids.items():
    name = os.path.basename(path)
    lines.append(f'\t\t\t\t{bid} /* {name} in Sources */,')
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXSourcesBuildPhase section */")
lines.append("")

# XCBuildConfiguration
COMMON_SETTINGS = """
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CODE_SIGN_STYLE = Automatic;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.9;"""

lines.append("/* Begin XCBuildConfiguration section */")

# Project debug
lines.append(f'\t\t{DEBUG_CONFIG_ID} /* Debug */ = {{')
lines.append('\t\t\tisa = XCBuildConfiguration;')
lines.append('\t\t\tbuildSettings = {')
lines.append(COMMON_SETTINGS)
lines.append('\t\t\t};')
lines.append('\t\t\tname = Debug;')
lines.append('\t\t};')

# Project release
lines.append(f'\t\t{RELEASE_CONFIG_ID} /* Release */ = {{')
lines.append('\t\t\tisa = XCBuildConfiguration;')
lines.append('\t\t\tbuildSettings = {')
lines.append('\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;')
lines.append('\t\t\t\tMAACOSX_DEPLOYMENT_TARGET = 13.0;')
lines.append('\t\t\t\tSWIFT_VERSION = 5.9;')
lines.append('\t\t\t\tSDKROOT = macosx;')
lines.append('\t\t\t};')
lines.append('\t\t\tname = Release;')
lines.append('\t\t};')

# Target debug
TARGET_SETTINGS = """
				CODE_SIGN_ENTITLEMENTS = Resources/MeetingMemo.entitlements;
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				DEVELOPMENT_TEAM = "";
				ENABLE_HARDENED_RUNTIME = YES;
				INFOPLIST_FILE = Resources/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				PRODUCT_BUNDLE_IDENTIFIER = "com.meetingmemo.app";
				PRODUCT_NAME = "Meeting Memo";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.9;"""

lines.append(f'\t\t{TARGET_DEBUG_CONFIG_ID} /* Debug */ = {{')
lines.append('\t\t\tisa = XCBuildConfiguration;')
lines.append('\t\t\tbuildSettings = {')
lines.append(TARGET_SETTINGS)
lines.append('\t\t\t};')
lines.append('\t\t\tname = Debug;')
lines.append('\t\t};')

TARGET_RELEASE_SETTINGS = """
				CODE_SIGN_ENTITLEMENTS = Resources/MeetingMemo.entitlements;
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				DEVELOPMENT_TEAM = "";
				ENABLE_HARDENED_RUNTIME = YES;
				INFOPLIST_FILE = Resources/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				PRODUCT_BUNDLE_IDENTIFIER = "com.meetingmemo.app";
				PRODUCT_NAME = "Meeting Memo";
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_VERSION = 5.9;"""

lines.append(f'\t\t{TARGET_RELEASE_CONFIG_ID} /* Release */ = {{')
lines.append('\t\t\tisa = XCBuildConfiguration;')
lines.append('\t\t\tbuildSettings = {')
lines.append(TARGET_RELEASE_SETTINGS)
lines.append('\t\t\t};')
lines.append('\t\t\tname = Release;')
lines.append('\t\t};')

lines.append("/* End XCBuildConfiguration section */")
lines.append("")

# XCConfigurationList
lines.append("/* Begin XCConfigurationList section */")
lines.append(f'\t\t{CONFIG_LIST_PROJECT_ID} /* Build configuration list for PBXProject "MeetingMemo" */ = {{')
lines.append('\t\t\tisa = XCConfigurationList;')
lines.append('\t\t\tbuildConfigurations = (')
lines.append(f'\t\t\t\t{DEBUG_CONFIG_ID} /* Debug */,')
lines.append(f'\t\t\t\t{RELEASE_CONFIG_ID} /* Release */,')
lines.append('\t\t\t);')
lines.append('\t\t\tdefaultConfigurationIsVisible = 0;')
lines.append('\t\t\tdefaultConfigurationName = Release;')
lines.append('\t\t};')

lines.append(f'\t\t{CONFIG_LIST_TARGET_ID} /* Build configuration list for PBXNativeTarget "MeetingMemo" */ = {{')
lines.append('\t\t\tisa = XCConfigurationList;')
lines.append('\t\t\tbuildConfigurations = (')
lines.append(f'\t\t\t\t{TARGET_DEBUG_CONFIG_ID} /* Debug */,')
lines.append(f'\t\t\t\t{TARGET_RELEASE_CONFIG_ID} /* Release */,')
lines.append('\t\t\t);')
lines.append('\t\t\tdefaultConfigurationIsVisible = 0;')
lines.append('\t\t\tdefaultConfigurationName = Release;')
lines.append('\t\t};')
lines.append("/* End XCConfigurationList section */")
lines.append("")

lines.append("\t};")
lines.append(f'\trootObject = {PROJECT_ID} /* Project object */;')
lines.append("}")

# Write output
xcodeproj_dir = os.path.join(WORKSPACE, "MeetingMemo.xcodeproj")
os.makedirs(xcodeproj_dir, exist_ok=True)
pbxproj_path = os.path.join(xcodeproj_dir, "project.pbxproj")
with open(pbxproj_path, "w") as f:
    f.write("\n".join(lines))

print(f"✅ Generated: {pbxproj_path}")
print(f"   Swift files included: {len(file_ids)}")
print(f"   Resource files: {len(res_ids)}")
