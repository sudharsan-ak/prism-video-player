#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

// Persists Prism's settings to a local JSON file under the user's
// AppData, same shape as the Electron build's settings.json: recent
// files, per-file resume positions, per-file bookmarks, volume, and
// the chosen theme. Nothing here ever leaves the machine.
class SettingsStore : public QObject {
    Q_OBJECT
    Q_PROPERTY(QStringList recentFiles READ recentFiles NOTIFY recentFilesChanged)
    Q_PROPERTY(int volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(QString themeName READ themeName WRITE setThemeName NOTIFY themeNameChanged)
    Q_PROPERTY(bool resumeEnabled READ resumeEnabled WRITE setResumeEnabled NOTIFY resumeEnabledChanged)
    Q_PROPERTY(QString seekBarThickness READ seekBarThickness WRITE setSeekBarThickness NOTIFY seekBarThicknessChanged)

public:
    explicit SettingsStore(QObject *parent = nullptr);

    QStringList recentFiles() const { return m_recentFiles; }
    int volume() const { return m_volume; }
    void setVolume(int v);
    QString themeName() const { return m_themeName; }
    void setThemeName(const QString &name);
    bool resumeEnabled() const { return m_resumeEnabled; }
    void setResumeEnabled(bool enabled);

    QString seekBarThickness() const { return m_seekBarThickness; }
    void setSeekBarThickness(const QString &thickness);

    Q_INVOKABLE void bumpRecent(const QString &path);
    Q_INVOKABLE void clearRecent();
    Q_INVOKABLE void removeRecent(const QString &path);
    Q_INVOKABLE double resumePositionFor(const QString &path) const;
    Q_INVOKABLE void setResumePositionFor(const QString &path, double seconds);
    Q_INVOKABLE void clearResumePositionFor(const QString &path);

    Q_INVOKABLE QVariantList bookmarksFor(const QString &path) const;
    Q_INVOKABLE void addBookmark(const QString &path, double time, const QString &label);
    Q_INVOKABLE void removeBookmark(const QString &path, double time);

    Q_INVOKABLE void save();
    Q_INVOKABLE QString capturesFolderPath() const;

signals:
    void recentFilesChanged();
    void volumeChanged();
    void themeNameChanged();
    void seekBarThicknessChanged();
    void resumeEnabledChanged();

private:
    void load();
    QString settingsFilePath() const;

    QStringList m_recentFiles;
    int m_volume = 80;
    QString m_themeName = QStringLiteral("warmGlass");
    bool m_resumeEnabled = true;
    QString m_seekBarThickness = QStringLiteral("slim");
    QVariantMap m_resumePositions;   // path -> seconds
    QVariantMap m_bookmarks;         // path -> list of {time, label}
};
