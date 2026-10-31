#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>

#include "mpvobject.h"
#include "playercontroller.h"
#include "settingsstore.h"
#include "themecontroller.h"
#include "videoexportcontroller.h"
#include "videothumbnailcontroller.h"

int main(int argc, char *argv[])
{
    // libmpv's render API is wired through OpenGL (see mpvobject.cpp);
    // Qt Quick's default RHI backend on Windows is Direct3D11, which
    // would make the FBO item a no-op for mpv's GL context. Forcing
    // OpenGL here is what makes the video surface actually paint.
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);

    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("Prism"));
    app.setOrganizationName(QStringLiteral("Prism"));

    qmlRegisterType<MpvObject>("Prism", 1, 0, "MpvObject");

    SettingsStore settings;
    ThemeController themeController(&settings);
    PlayerController playerController(&settings);
    VideoExportController videoExportController(&settings);
    VideoThumbnailController videoThumbnailController;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("settingsStore", &settings);
    engine.rootContext()->setContextProperty("themeController", &themeController);
    engine.rootContext()->setContextProperty("playerController", &playerController);
    engine.rootContext()->setContextProperty("videoExportController", &videoExportController);
    engine.rootContext()->setContextProperty("videoThumbnailController", &videoThumbnailController);

    QObject::connect(
        &engine, &QQmlApplicationEngine::warnings,
        &app, [](const QList<QQmlError> &warnings) {
            for (const QQmlError &e : warnings)
                fprintf(stderr, "QML WARNING: %s\n", qPrintable(e.toString()));
        });

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed,
        &app, [](const QUrl &url) {
            fprintf(stderr, "QML object creation failed for: %s\n", qPrintable(url.toString()));
            QCoreApplication::exit(-1);
        },
        Qt::QueuedConnection);

    engine.loadFromModule("Prism", "Main");

    if (engine.rootObjects().isEmpty()) {
        fprintf(stderr, "Prism: engine.rootObjects() is empty after loadFromModule.\n");
        return -1;
    }

    return app.exec();
}
