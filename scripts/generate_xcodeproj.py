#!/usr/bin/env python3
"""Generate SleepingRoutineForZy.xcodeproj from sources on disk."""
from __future__ import annotations

import os
import random
import string
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def new_id() -> str:
    return "".join(random.choice("0123456789ABCDEF") for _ in range(24))


def main() -> None:
    app_dir = ROOT / "SleepingRoutineForZy"
    tests_dir = ROOT / "SleepingRoutineForZyTests"
    uitests_dir = ROOT / "SleepingRoutineForZyUITests"

    app_swift = sorted(app_dir.rglob("*.swift"))
    app_plist = list(app_dir.rglob("Info.plist"))
    app_strings = list(app_dir.rglob("*.xcstrings"))
    test_swift = sorted(tests_dir.rglob("*.swift"))
    uitest_swift = sorted(uitests_dir.rglob("*.swift"))

    ids: dict[str, str] = {}

    def fid(key: str) -> str:
        if key not in ids:
            ids[key] = new_id()
        return ids[key]

    project_id = new_id()
    main_group = new_id()
    products_group = new_id()
    app_group = new_id()
    tests_group = new_id()
    uitests_group = new_id()
    config_group = new_id()
    sources_app = new_id()
    resources_app = new_id()
    frameworks_app = new_id()
    sources_tests = new_id()
    frameworks_tests = new_id()
    sources_uitests = new_id()
    frameworks_uitests = new_id()
    app_target = new_id()
    tests_target = new_id()
    uitests_target = new_id()
    app_product = new_id()
    tests_product = new_id()
    uitests_product = new_id()
    project_configs = new_id()
    app_configs = new_id()
    tests_configs = new_id()
    uitests_configs = new_id()
    dbg_proj, rel_proj = new_id(), new_id()
    dbg_app, rel_app = new_id(), new_id()
    dbg_tests, rel_tests = new_id(), new_id()
    dbg_uitests, rel_uitests = new_id(), new_id()
    dbg_xc, rel_xc, shared_xc = new_id(), new_id(), new_id()
    assets_id, assets_build = new_id(), new_id()
    proxy1, proxy2, dep1, dep2 = new_id(), new_id(), new_id(), new_id()

    build_files: list[str] = []
    file_refs: list[str] = []
    app_source_builds: list[str] = []
    app_resource_builds: list[str] = []
    test_source_builds: list[str] = []
    uitest_source_builds: list[str] = []
    app_children: list[str] = []
    test_children: list[str] = []
    uitest_children: list[str] = []

    def rel(path: Path) -> str:
        return path.relative_to(ROOT).as_posix()

    for path in app_swift + app_plist + app_strings:
        r = rel(path)
        ref = fid(r)
        if path.suffix == ".swift":
            ftype = "sourcecode.swift"
        elif path.suffix == ".plist":
            ftype = "text.plist.xml"
        else:
            ftype = "text.json.xcstrings"
        file_refs.append(
            f"\t\t{ref} /* {path.name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = \"{r}\"; sourceTree = SOURCE_ROOT; }};"
        )
        app_children.append(f"\t\t\t\t{ref} /* {path.name} */,")
        if path.suffix == ".swift":
            bid = new_id()
            build_files.append(
                f"\t\t{bid} /* {path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {path.name} */; }};"
            )
            app_source_builds.append(f"\t\t\t\t{bid} /* {path.name} in Sources */,")
        elif path.suffix == ".xcstrings":
            bid = new_id()
            build_files.append(
                f"\t\t{bid} /* {path.name} in Resources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {path.name} */; }};"
            )
            app_resource_builds.append(f"\t\t\t\t{bid} /* {path.name} in Resources */,")

    assets_rel = "SleepingRoutineForZy/Resources/Assets.xcassets"
    file_refs.append(
        f"\t\t{assets_id} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = \"{assets_rel}\"; sourceTree = SOURCE_ROOT; }};"
    )
    app_children.append(f"\t\t\t\t{assets_id} /* Assets.xcassets */,")
    build_files.append(
        f"\t\t{assets_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_id} /* Assets.xcassets */; }};"
    )
    app_resource_builds.append(f"\t\t\t\t{assets_build} /* Assets.xcassets in Resources */,")

    for path in test_swift:
        r = rel(path)
        ref = fid(r)
        file_refs.append(
            f"\t\t{ref} /* {path.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{r}\"; sourceTree = SOURCE_ROOT; }};"
        )
        test_children.append(f"\t\t\t\t{ref} /* {path.name} */,")
        bid = new_id()
        build_files.append(
            f"\t\t{bid} /* {path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {path.name} */; }};"
        )
        test_source_builds.append(f"\t\t\t\t{bid} /* {path.name} in Sources */,")

    for path in uitest_swift:
        r = rel(path)
        ref = fid(r)
        file_refs.append(
            f"\t\t{ref} /* {path.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{r}\"; sourceTree = SOURCE_ROOT; }};"
        )
        uitest_children.append(f"\t\t\t\t{ref} /* {path.name} */,")
        bid = new_id()
        build_files.append(
            f"\t\t{bid} /* {path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {path.name} */; }};"
        )
        uitest_source_builds.append(f"\t\t\t\t{bid} /* {path.name} in Sources */,")

    for ref, name, path in (
        (dbg_xc, "Debug.xcconfig", "Config/Debug.xcconfig"),
        (rel_xc, "Release.xcconfig", "Config/Release.xcconfig"),
        (shared_xc, "Shared.xcconfig", "Config/Shared.xcconfig"),
    ):
        file_refs.append(
            f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = {path}; sourceTree = SOURCE_ROOT; }};"
        )

    file_refs.append(
        f"\t\t{app_product} /* SleepingRoutineForZy.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SleepingRoutineForZy.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    file_refs.append(
        f"\t\t{tests_product} /* SleepingRoutineForZyTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = SleepingRoutineForZyTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    file_refs.append(
        f"\t\t{uitests_product} /* SleepingRoutineForZyUITests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = SleepingRoutineForZyUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )

    def app_cfg(cfg_id: str, name: str, xc: str) -> str:
        return f"""\t\t{cfg_id} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReference = {xc} /* {name}.xcconfig */;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = SleepingRoutineForZy/Resources/Info.plist;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = SleepingRoutineForZy/SleepingRoutineForZy.entitlements;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.zy.sleepingroutine;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSUPPORTS_MACCATALYST = NO;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t}};
\t\t\tname = {name};
\t\t}};"""

    def tests_cfg(cfg_id: str, name: str) -> str:
        return f"""\t\t{cfg_id} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.4;
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.zy.sleepingroutine.tests;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/SleepingRoutineForZy.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SleepingRoutineForZy";
\t\t\t}};
\t\t\tname = {name};
\t\t}};"""

    def uitests_cfg(cfg_id: str, name: str) -> str:
        return f"""\t\t{cfg_id} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.zy.sleepingroutine.uitests;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t\tTEST_TARGET_NAME = SleepingRoutineForZy;
\t\t\t}};
\t\t\tname = {name};
\t\t}};"""

    pbx = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(file_refs)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{frameworks_app} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{frameworks_tests} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{frameworks_uitests} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{main_group} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{app_group} /* SleepingRoutineForZy */,
\t\t\t\t{tests_group} /* SleepingRoutineForZyTests */,
\t\t\t\t{uitests_group} /* SleepingRoutineForZyUITests */,
\t\t\t\t{config_group} /* Config */,
\t\t\t\t{products_group} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{products_group} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{app_product} /* SleepingRoutineForZy.app */,
\t\t\t\t{tests_product} /* SleepingRoutineForZyTests.xctest */,
\t\t\t\t{uitests_product} /* SleepingRoutineForZyUITests.xctest */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{app_group} /* SleepingRoutineForZy */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{chr(10).join(app_children)}
\t\t\t);
\t\t\tname = SleepingRoutineForZy;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{tests_group} /* SleepingRoutineForZyTests */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{chr(10).join(test_children)}
\t\t\t);
\t\t\tname = SleepingRoutineForZyTests;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{uitests_group} /* SleepingRoutineForZyUITests */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{chr(10).join(uitest_children)}
\t\t\t);
\t\t\tname = SleepingRoutineForZyUITests;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{config_group} /* Config */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{dbg_xc} /* Debug.xcconfig */,
\t\t\t\t{rel_xc} /* Release.xcconfig */,
\t\t\t\t{shared_xc} /* Shared.xcconfig */,
\t\t\t);
\t\t\tname = Config;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{app_target} /* SleepingRoutineForZy */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {app_configs} /* Build configuration list for PBXNativeTarget "SleepingRoutineForZy" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_app} /* Sources */,
\t\t\t\t{frameworks_app} /* Frameworks */,
\t\t\t\t{resources_app} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = SleepingRoutineForZy;
\t\t\tproductName = SleepingRoutineForZy;
\t\t\tproductReference = {app_product} /* SleepingRoutineForZy.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{tests_target} /* SleepingRoutineForZyTests */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {tests_configs} /* Build configuration list for PBXNativeTarget "SleepingRoutineForZyTests" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_tests} /* Sources */,
\t\t\t\t{frameworks_tests} /* Frameworks */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{dep1} /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = SleepingRoutineForZyTests;
\t\t\tproductName = SleepingRoutineForZyTests;
\t\t\tproductReference = {tests_product} /* SleepingRoutineForZyTests.xctest */;
\t\t\tproductType = "com.apple.product-type.bundle.unit-test";
\t\t}};
\t\t{uitests_target} /* SleepingRoutineForZyUITests */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {uitests_configs} /* Build configuration list for PBXNativeTarget "SleepingRoutineForZyUITests" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_uitests} /* Sources */,
\t\t\t\t{frameworks_uitests} /* Frameworks */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{dep2} /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = SleepingRoutineForZyUITests;
\t\t\tproductName = SleepingRoutineForZyUITests;
\t\t\tproductReference = {uitests_product} /* SleepingRoutineForZyUITests.xctest */;
\t\t\tproductType = "com.apple.product-type.bundle.ui-testing";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project_id} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{app_target} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t}};
\t\t\t\t\t{tests_target} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t\tTestTargetID = {app_target};
\t\t\t\t\t}};
\t\t\t\t\t{uitests_target} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t\tTestTargetID = {app_target};
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {project_configs} /* Build configuration list for PBXProject "SleepingRoutineForZy" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_group};
\t\t\tproductRefGroup = {products_group} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{app_target} /* SleepingRoutineForZy */,
\t\t\t\t{tests_target} /* SleepingRoutineForZyTests */,
\t\t\t\t{uitests_target} /* SleepingRoutineForZyUITests */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{resources_app} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(app_resource_builds)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{sources_app} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(app_source_builds)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{sources_tests} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(test_source_builds)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{sources_uitests} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(uitest_source_builds)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXContainerItemProxy section */
\t\t{proxy1} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {project_id} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {app_target};
\t\t\tremoteInfo = SleepingRoutineForZy;
\t\t}};
\t\t{proxy2} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {project_id} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {app_target};
\t\t\tremoteInfo = SleepingRoutineForZy;
\t\t}};
/* End PBXContainerItemProxy section */

/* Begin PBXTargetDependency section */
\t\t{dep1} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {app_target} /* SleepingRoutineForZy */;
\t\t\ttargetProxy = {proxy1} /* PBXContainerItemProxy */;
\t\t}};
\t\t{dep2} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {app_target} /* SleepingRoutineForZy */;
\t\t\ttargetProxy = {proxy2} /* PBXContainerItemProxy */;
\t\t}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
\t\t{dbg_proj} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.4;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{rel_proj} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.4;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
{app_cfg(dbg_app, "Debug", dbg_xc)}
{app_cfg(rel_app, "Release", rel_xc)}
{tests_cfg(dbg_tests, "Debug")}
{tests_cfg(rel_tests, "Release")}
{uitests_cfg(dbg_uitests, "Debug")}
{uitests_cfg(rel_uitests, "Release")}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{project_configs} /* Build configuration list for PBXProject "SleepingRoutineForZy" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{dbg_proj} /* Debug */,
\t\t\t\t{rel_proj} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{app_configs} /* Build configuration list for PBXNativeTarget "SleepingRoutineForZy" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{dbg_app} /* Debug */,
\t\t\t\t{rel_app} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{tests_configs} /* Build configuration list for PBXNativeTarget "SleepingRoutineForZyTests" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{dbg_tests} /* Debug */,
\t\t\t\t{rel_tests} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{uitests_configs} /* Build configuration list for PBXNativeTarget "SleepingRoutineForZyUITests" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{dbg_uitests} /* Debug */,
\t\t\t\t{rel_uitests} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {project_id} /* Project object */;
}}
"""

    proj_dir = ROOT / "SleepingRoutineForZy.xcodeproj"
    proj_dir.mkdir(parents=True, exist_ok=True)
    (proj_dir / "project.pbxproj").write_text(pbx, encoding="utf-8")

    scheme_dir = proj_dir / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{app_target}" BuildableName = "SleepingRoutineForZy.app" BlueprintName = "SleepingRoutineForZy" ReferencedContainer = "container:SleepingRoutineForZy.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES" shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference skipped = "NO"><BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{tests_target}" BuildableName = "SleepingRoutineForZyTests.xctest" BlueprintName = "SleepingRoutineForZyTests" ReferencedContainer = "container:SleepingRoutineForZy.xcodeproj"/></TestableReference>
         <TestableReference skipped = "NO"><BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{uitests_target}" BuildableName = "SleepingRoutineForZyUITests.xctest" BlueprintName = "SleepingRoutineForZyUITests" ReferencedContainer = "container:SleepingRoutineForZy.xcodeproj"/></TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{app_target}" BuildableName = "SleepingRoutineForZy.app" BlueprintName = "SleepingRoutineForZy" ReferencedContainer = "container:SleepingRoutineForZy.xcodeproj"/>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{app_target}" BuildableName = "SleepingRoutineForZy.app" BlueprintName = "SleepingRoutineForZy" ReferencedContainer = "container:SleepingRoutineForZy.xcodeproj"/>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"/>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"/>
</Scheme>
"""
    (scheme_dir / "SleepingRoutineForZy.xcscheme").write_text(scheme, encoding="utf-8")
    print(f"Generated project with {len(app_swift)} app swift, {len(test_swift)} tests, {len(uitest_swift)} uitests")


if __name__ == "__main__":
    main()
