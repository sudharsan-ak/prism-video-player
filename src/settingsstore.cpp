#include "settingsstore.h"

#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonValue>
#include <QSaveFile>
#include <QDebug>
#include <algorithm>

SettingsStore::SettingsStore(QObject *parent) : QObject(parent)
{
    load();
}

QString SettingsStore::capturesFolderPath() const
{
    const QString pictures = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    return pictures + QStringLiteral("/Prism Captures");
}

QString SettingsStore::settingsFilePath() const
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dir);
    return dir + QStringLiteral("/settings.json");
}

void SettingsStore::load()
{
    QFile file(settingsFilePath());
    if (!file.open(QIODevice::ReadOnly))
        return; // first launch, defaults stand

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject())
        return;

    const QJsonObject root = doc.object();

    if (root.contains("recent") && root["recent"].isArray()) {
        m_recentFiles.clear();
        for (const QJsonValue &v : root["recent"].toArray()) {
            if (v.isString())
                m_recentFiles.append(v.toString());
        }
    }
    if (root.contains("volume"))
        m_volume = root["volume"].toInt(80);
    if (root.contains("theme"))
        m_themeName = root["theme"].toString(QStringLiteral("warmGlass"));
    if (root.contains("resumeEnabled"))
        m_resumeEnabled = root["resumeEnabled"].toBool(true);
    // Invalid or older settings files fall back to Slim (4px).
    const QString thickness = root.value("seekBarThickness").toString(QStringLiteral("slim"));
    if (thickness == QStringLiteral("slim") || thickness == QStringLiteral("medium")
        || thickness == QStringLiteral("thick"))
        m_seekBarThickness = thickness;
    m_keepBackupOnReplace = root.value("keepBackupOnReplace").toBool(false);
    const QString preset = root.value("encodingPreset").toString(QStringLiteral("veryfast"));
    if (preset == QStringLiteral("ultrafast") || preset == QStringLiteral("veryfast") ||
        preset == QStringLiteral("fast") || preset == QStringLiteral("medium") ||
        preset == QStringLiteral("slow"))
        m_encodingPreset = preset;
    const QString gifPreset = root.value("gifQualityPreset").toString(QStringLiteral("balanced"));
    if (gifPreset == QStringLiteral("high") || gifPreset == QStringLiteral("balanced") ||
        gifPreset == QStringLiteral("compact"))
        m_gifQualityPreset = gifPreset;
    const QString mp4Mode = root.value("mp4ExportMode").toString(QStringLiteral("auto"));
    if (mp4Mode == QStringLiteral("auto") || mp4Mode == QStringLiteral("saveAs") ||
        mp4Mode == QStringLiteral("replace"))
        m_mp4ExportMode = mp4Mode;
    const QString gifMode = root.value("gifExportMode").toString(QStringLiteral("auto"));
    if (gifMode == QStringLiteral("auto") || gifMode == QStringLiteral("saveAs"))
        m_gifExportMode = gifMode;
    if (root.contains("resume") && root["resume"].isObject())
        m_resumePositions = root["resume"].toObject().toVariantMap();
    if (root.contains("bookmarks") && root["bookmarks"].isObject())
        m_bookmarks = root["bookmarks"].toObject().toVariantMap();
}

void SettingsStore::save()
{
    QJsonObject root;

    QJsonArray recent;
    for (const QString &r : m_recentFiles)
        recent.append(r);
    root["recent"] = recent;

    root["volume"] = m_volume;
    root["theme"] = m_themeName;
    root["resumeEnabled"] = m_resumeEnabled;
    root["seekBarThickness"] = m_seekBarThickness;
    root["keepBackupOnReplace"] = m_keepBackupOnReplace;
    root["encodingPreset"] = m_encodingPreset;
    root["gifQualityPreset"] = m_gifQualityPreset;
    root["mp4ExportMode"] = m_mp4ExportMode;
    root["gifExportMode"] = m_gifExportMode;
    root["resume"] = QJsonObject::fromVariantMap(m_resumePositions);
    root["bookmarks"] = QJsonObject::fromVariantMap(m_bookmarks);

    // Atomic write (temp file + rename), same safeguard the Electron
    // build used, so a crash mid-save can't corrupt settings.json.
    QSaveFile file(settingsFilePath());
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning() << "Prism: cannot write settings file";
        return;
    }
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    file.commit();
}

void SettingsStore::setVolume(int v)
{
    v = qBound(0, v, 100);
    if (v == m_volume)
        return;
    m_volume = v;
    emit volumeChanged();
}

void SettingsStore::setThemeName(const QString &name)
{
    if (name == m_themeName)
        return;
    m_themeName = name;
    emit themeNameChanged();
    save();
}

void SettingsStore::setResumeEnabled(bool enabled)
{
    if (enabled == m_resumeEnabled)
        return;
    m_resumeEnabled = enabled;
    emit resumeEnabledChanged();
    save();
}

void SettingsStore::setSeekBarThickness(const QString &thickness)
{
    if (thickness != QStringLiteral("slim") && thickness != QStringLiteral("medium")
        && thickness != QStringLiteral("thick"))
        return;
    if (thickness == m_seekBarThickness)
        return;
    m_seekBarThickness = thickness;
    emit seekBarThicknessChanged();
    save();
}

void SettingsStore::setKeepBackupOnReplace(bool enabled)
{
    if (m_keepBackupOnReplace == enabled)
        return;
    m_keepBackupOnReplace = enabled;
    emit keepBackupOnReplaceChanged();
    save();
}

void SettingsStore::setEncodingPreset(const QString &preset)
{
    if (preset != QStringLiteral("ultrafast") && preset != QStringLiteral("veryfast") &&
        preset != QStringLiteral("fast") && preset != QStringLiteral("medium") &&
        preset != QStringLiteral("slow"))
        return;
    if (m_encodingPreset == preset)
        return;
    m_encodingPreset = preset;
    emit encodingPresetChanged();
    save();
}

void SettingsStore::setGifQualityPreset(const QString &preset)
{
    if (preset != QStringLiteral("high") && preset != QStringLiteral("balanced") &&
        preset != QStringLiteral("compact"))
        return;
    if (preset == m_gifQualityPreset)
        return;
    m_gifQualityPreset = preset;
    emit gifQualityPresetChanged();
    save();
}

void SettingsStore::setMp4ExportMode(const QString &mode)
{
    if (mode != QStringLiteral("auto") && mode != QStringLiteral("saveAs") &&
        mode != QStringLiteral("replace"))
        return;
    if (mode == m_mp4ExportMode)
        return;
    m_mp4ExportMode = mode;
    emit mp4ExportModeChanged();
    save();
}

void SettingsStore::setGifExportMode(const QString &mode)
{
    if (mode != QStringLiteral("auto") && mode != QStringLiteral("saveAs"))
        return;
    if (mode == m_gifExportMode)
        return;
    m_gifExportMode = mode;
    emit gifExportModeChanged();
    save();
}

void SettingsStore::bumpRecent(const QString &path)
{
    m_recentFiles.removeAll(path);
    m_recentFiles.prepend(path);
    while (m_recentFiles.size() > 30)
        m_recentFiles.removeLast();
    emit recentFilesChanged();
    save();
}

void SettingsStore::clearRecent()
{
    m_recentFiles.clear();
    emit recentFilesChanged();
    save();
}

void SettingsStore::removeRecent(const QString &path)
{
    if (m_recentFiles.removeAll(path) > 0) {
        emit recentFilesChanged();
        save();
    }
}

double SettingsStore::resumePositionFor(const QString &path) const
{
    return m_resumePositions.value(path, 0.0).toDouble();
}

void SettingsStore::setResumePositionFor(const QString &path, double seconds)
{
    m_resumePositions[path] = seconds;
    // Debounced persistence is handled by the caller (PlayerController)
    // to avoid writing to disk on every single position tick.
}

void SettingsStore::clearResumePositionFor(const QString &path)
{
    m_resumePositions.remove(path);
}

QVariantList SettingsStore::bookmarksFor(const QString &path) const
{
    return m_bookmarks.value(path).toList();
}

void SettingsStore::addBookmark(const QString &path, double time, const QString &label)
{
    QVariantList list = m_bookmarks.value(path).toList();
    for (const QVariant &existing : list) {
        const QVariantMap m = existing.toMap();
        if (qAbs(m.value("time").toDouble() - time) < 0.5)
            return; // already bookmarked near this point
    }
    QVariantMap entry;
    entry["time"] = time;
    entry["label"] = label;
    list.append(entry);
    std::sort(list.begin(), list.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value("time").toDouble() < b.toMap().value("time").toDouble();
    });
    while (list.size() > 100)
        list.removeLast();
    m_bookmarks[path] = list;
    save();
}

void SettingsStore::removeBookmark(const QString &path, double time)
{
    QVariantList list = m_bookmarks.value(path).toList();
    QVariantList filtered;
    for (const QVariant &existing : list) {
        if (!qFuzzyCompare(existing.toMap().value("time").toDouble() + 1.0, time + 1.0))
            filtered.append(existing);
    }
    m_bookmarks[path] = filtered;
    save();
}
