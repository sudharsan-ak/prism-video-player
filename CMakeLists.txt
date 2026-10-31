cmake_minimum_required(VERSION 3.21)
project(Prism LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Qt6 REQUIRED COMPONENTS Core Gui OpenGL Qml Quick QuickControls2)

qt_standard_project_setup(REQUIRES 6.5)
qt_policy(SET QTP0004 NEW)

set(MPV_ROOT "${CMAKE_SOURCE_DIR}/vendor/libmpv")

qt_add_executable(Prism
    src/main.cpp
    src/mpvobject.cpp
    src/mpvobject.h
    src/playercontroller.cpp
    src/playercontroller.h
    src/settingsstore.cpp
    src/settingsstore.h
    src/themecontroller.cpp
    src/themecontroller.h
    src/videoexportcontroller.cpp
    src/videoexportcontroller.h
    src/exportqueuecontroller.cpp
    src/exportqueuecontroller.h
    src/videothumbnailcontroller.cpp
    src/videothumbnailcontroller.h
    resources/prism.rc
)

qt_add_qml_module(Prism
    URI Prism
    VERSION 1.0
    QML_FILES
        qml/ExportQueuePanel.qml
        qml/Main.qml
        qml/TopBar.qml
        qml/TopMenuLabel.qml
        qml/FileMenu.qml
        qml/PlayMenu.qml
        qml/VideoMenu.qml
        qml/AudioMenu.qml
        qml/SubtitleMenu.qml
        qml/ToolsMenu.qml
        qml/SettingsMenu.qml
        qml/PlaybackMenu.qml
        qml/MoreMenu.qml
        qml/ThemedSeekBar.qml
        qml/ThemedComboBox.qml
        qml/ContextMenu.qml
        qml/LibraryPanel.qml
        qml/AdjustmentsPanel.qml
        qml/EditorPanel.qml
        qml/CropControls.qml
        qml/CropOverlay.qml
        qml/EditorTimeline.qml
        qml/BottomControlBar.qml
        qml/FullscreenOverlay.qml
        qml/OsdOverlay.qml
        qml/VideoSurface.qml
    RESOURCES
        resources/icon.ico
        resources/icon_topbar.png
)

target_include_directories(Prism PRIVATE
    ${MPV_ROOT}/include
)

target_link_libraries(Prism PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::OpenGL
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    "${MPV_ROOT}/lib/libmpv.lib"
)

set_target_properties(Prism PROPERTIES
    WIN32_EXECUTABLE TRUE
)

# Copy libmpv-2.dll next to the built executable so it runs without
# installing anything system-wide. This is the only native runtime
# dependency Prism has beyond the Qt DLLs windeployqt handles.
add_custom_command(TARGET Prism POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${MPV_ROOT}/bin/libmpv-2.dll"
        "$<TARGET_FILE_DIR:Prism>/libmpv-2.dll"
)

# Optional local FFmpeg binary for native video exports. The repository
# does not ship FFmpeg; users supply a properly licensed Windows build.
if(EXISTS "${CMAKE_SOURCE_DIR}/vendor/ffmpeg/bin/ffmpeg.exe")
    add_custom_command(TARGET Prism POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/vendor/ffmpeg/bin/ffmpeg.exe"
            "$<TARGET_FILE_DIR:Prism>/ffmpeg.exe"
    )
endif()
