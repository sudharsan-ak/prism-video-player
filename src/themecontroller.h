#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QVariantList>

class SettingsStore;

// Owns the six locked Phase 1 themes as token maps (colors, gradients,
// surface treatment) and exposes the active one to QML. Adding or
// removing a theme later means editing buildThemeTable(), nothing in
// the UI layer needs to change (see PHASE1_PLAN_QT.md section 6.4).
class ThemeController : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString activeThemeName READ activeThemeName WRITE setActiveThemeName NOTIFY activeThemeChanged)
    Q_PROPERTY(QVariantMap tokens READ tokens NOTIFY activeThemeChanged)
    Q_PROPERTY(QVariantList availableThemes READ availableThemes CONSTANT)

public:
    explicit ThemeController(SettingsStore *settings, QObject *parent = nullptr);

    QString activeThemeName() const { return m_activeThemeName; }
    void setActiveThemeName(const QString &name);
    QVariantMap tokens() const;
    QVariantList availableThemes() const;

signals:
    void activeThemeChanged();

private:
    void buildThemeTable();

    SettingsStore *m_settings;
    QString m_activeThemeName;
    QMap<QString, QVariantMap> m_themes;
    QList<QPair<QString, QString>> m_themeOrder; // id, display name
};
