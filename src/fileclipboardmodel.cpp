/*
 * This file is part of File Browser.
 *
 * SPDX-FileCopyrightText: 2022-2023 Mirian Margiani
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * File Browser is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version.
 *
 * File Browser is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <https://www.gnu.org/licenses/>.
 */

#include <QDebug>
#include "fileclipboardmodel.h"
#include "statfileinfo.h"
#include "configfilemonitor.h"

#include "settingshandler.h"

DEFINE_ENUM_REGISTRATION_FUNCTION(FileClipboard) {
    REGISTER_ENUM_CONTAINER(FileClipMode)
}

enum {
    FullPathRole =        Qt::DisplayRole,
    DirRole =             Qt::UserRole + 10,
};

QVariant PathsModel::data(const QModelIndex &index, int role) const
{
    const auto& entry = QStringListModel::data(index, Qt::DisplayRole);
    if (!entry.isValid()) return entry;

    switch (role) {
    case Qt::DisplayRole:
        return entry.toString();

    case DirRole:
        return QFileInfo(entry.toString()).path();

    default:
        return QVariant();
    }
}

QHash<int, QByteArray> PathsModel::roleNames() const
{
    QHash<int, QByteArray> roles = QAbstractListModel::roleNames();
    roles.insert(FullPathRole, QByteArray("path"));
    roles.insert(DirRole, QByteArray("directory"));
    return roles;
}

FileClipboard::FileClipboard(QObject* parent)
    : QObject(parent), m_pathsModel(new PathsModel(this)), m_monitor(new ConfigFileMonitor(this))
{
    connect(this, &FileClipboard::pathsChanged, this, [&](){
        m_count = m_paths.count();
        m_pathsModel->setStringList(m_paths);
        emit countChanged();
    });

    m_monitor->reset(RawSettingsHandler::instance()->configDirectory() + "/clipboard.json");
    connect(m_monitor, &ConfigFileMonitor::configChanged, this, &FileClipboard::reload);
    reload();  // must be called after m_moniter->reset(...) because it relies on m_monitor->file()
}

FileClipboard::~FileClipboard()
{
    //
}

void FileClipboard::setPaths(const QStringList& paths, FileClipMode::Enum mode)
{
    setPaths(paths, mode, true);
}

void FileClipboard::forgetPath(QString path)
{
    QString validated = validatePath(path);
    if (validated.isEmpty()) return;

    int removed = m_paths.removeAll(validated);

    if (removed > 0) {
        emit pathsChanged();
        saveToDisk();
    }
}

void FileClipboard::forgetIndex(int index)
{
    if (index < 0 || index > m_count) {
        return;
    }

    m_paths.removeAt(index);
    emit pathsChanged();
    saveToDisk();
}

void FileClipboard::appendPath(QString path)
{
    QString validated = validatePath(path);

    if (validated.isEmpty()) {
        qDebug() << "cannot add invalid path to clipboard:" << path;
        return;
    } else if (m_paths.contains(validated)) {
        qDebug() << "path already in clipboard:" << validated;
        return;
    }

    m_paths.append(validated);
    emit pathsChanged();
    saveToDisk();
}

bool FileClipboard::hasPath(QString path)
{
    auto validated = validatePath(path);

    if (validated.isEmpty()) {
        return false;
    } else {
        return m_paths.contains(validated);
    }
}

void FileClipboard::clear()
{
    m_paths.clear();
    emit pathsChanged();
    saveToDisk();
}

QStringList FileClipboard::listExistingFiles(QString destDirectory, bool ignoreInCurrentDir, bool getNamesOnly)
{
    const QStringList& currentFiles = m_paths;

    if (currentFiles.isEmpty()) {
        return QStringList();
    }

    QDir destination(destDirectory);
    if (!destination.exists()) {
        return QStringList();
    }

    QStringList existingFiles;

    for (const auto& path : currentFiles) {
        QFileInfo fileInfo(path);
        QString newPath = destination.absoluteFilePath(fileInfo.fileName());

        // Are source and destination paths the same?
        // Note: Engine::pasteFiles() can create numbered copies.
        if (ignoreInCurrentDir && newPath == fileInfo.absoluteFilePath()) {
            continue;
        }

        // Is the destination directory inside the source directory?
        // Note: Engine::pasteFiles() will return an error.
        // FIXME: this is actually a safe operation and must be fixed in Engine::pasteFiles().
        if (fileInfo.isDir() && (newPath + QStringLiteral("/")).startsWith((path + QStringLiteral("/")))) {
            return QStringList();
        }

        if (QFile::exists(newPath)) {
            if (getNamesOnly) {
                existingFiles.append(fileInfo.fileName());
            } else {
                existingFiles.append(path);
            }
        }
    }

    return existingFiles;
}

int FileClipboard::count() const
{
    return m_count;
}

FileClipMode::Enum FileClipboard::mode() const
{
    return m_mode;
}

void FileClipboard::setMode(FileClipMode::Enum newMode)
{
    m_mode = newMode;
    emit modeChanged();
    saveToDisk();
}

const QStringList& FileClipboard::paths() const
{
    return m_paths;
}

PathsModel* FileClipboard::pathsModel() const
{
    return m_pathsModel;
}

void FileClipboard::reload()
{
    std::string read = m_monitor->readFile().toStdString();
    auto doc = QJsonDocument::fromJson(QByteArray::fromStdString(read));

    if (!doc.isObject()) {
        qDebug() << "clipboard file is invalid:" << m_monitor->readFile();
        return;
    }

    const auto obj = doc.object();
    const auto array = obj.value(QStringLiteral("paths")).toArray();
    QString savedModeString = obj.value(QStringLiteral("mode")).toString(QLatin1Literal());
    int savedMode = FileClipMode::Copy;

    if (!savedModeString.isEmpty()) {
        QMetaEnum metaEnum = QMetaEnum::fromType<FileClipMode::Enum>();
        savedMode = metaEnum.keyToValue(savedModeString.toStdString().c_str());
        if (savedMode < 0) savedMode = FileClipMode::Copy;
    }

    auto newMode = static_cast<FileClipMode::Enum>(savedMode);

    QStringList newPaths;
    for (const auto& i : array) {
        if (i.isString()) newPaths << i.toString();
    }

    setPaths(newPaths, newMode, false);
}

void FileClipboard::saveToDisk()
{
    ConfigFileMonitorBlocker blocker(m_monitor);

    qDebug() << "saving clipboard";
    QSaveFile outFile(m_monitor->file());

    if (!outFile.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Unbuffered)) {
        qWarning() << "failed to open a temporary file for saving clipboard";
        qWarning() << "clipboard contents will not be available in other app windows";
        return;
    }

    QMetaEnum metaEnum = QMetaEnum::fromType<FileClipMode::Enum>();
    QString modeString = metaEnum.valueToKey(m_mode);

    QJsonDocument doc;
    QJsonObject obj;

    obj.insert(QStringLiteral("mode"), m_paths.isEmpty() ? QLatin1Literal() : modeString);
    obj.insert(QStringLiteral("paths"), QJsonArray::fromStringList(m_paths));
    doc.setObject(obj);

    outFile.write(doc.toJson(QJsonDocument::Indented));

    if (!outFile.commit()) {
        qWarning() << "failed to save clipboard to" << m_monitor->file();
        qWarning() << "clipboard contents will not be available in other app windows";
        return;
    }

    qDebug() << "clipboard saved, start monitoring again";
}

void FileClipboard::setPaths(const QStringList& newPaths, FileClipMode::Enum mode, bool doSave)
{
    // don't use setMode(mode) here so we can emit both
    // signals at the same time and save only once
    m_mode = mode;

    QStringList toAdd;
    toAdd.reserve(newPaths.length());

    for (auto& i : newPaths) {
        auto validated = validatePath(i);

        if (!validated.isEmpty()) {
            toAdd.append(i);
        }
    }

    toAdd.removeDuplicates();
    m_paths = toAdd;

    emit pathsChanged();
    emit modeChanged();

    if (doSave) {
        saveToDisk();
    }
}

void FileClipboard::setPaths(const QStringList &newPaths)
{
    setPaths(newPaths, m_mode, true);
}

QString FileClipboard::validatePath(QString path)
{
    // - never allow special files (char/block/fifo/socket) in the clipboard
    // - never allow non-existent files
    // - make sure all paths are absolute
    // - note: duplicates are not allowed but are not checked by this method

    if (path.isEmpty()) return path;

    StatFileInfo info(path);

    if (info.isSystem()) {
        qDebug() << "cannot put special files in the clipboard:" << path;
        return QLatin1Literal();
    } else if (!info.exists()) {
        qDebug() << "cannot put non-existent files in the clipboard:" << path;
        return QLatin1Literal();
    } else {
        return info.absoluteFilePath();
    }
}

PathsModel::PathsModel(QObject* parent) : QStringListModel(parent)
{
    connect(this, &PathsModel::dataChanged, this, [&](const QModelIndex& topLeft,
                                                      const QModelIndex& bottomRight,
                                                      const QVector<int>& roles){
        Q_UNUSED(roles)
        emit dataChanged(topLeft, bottomRight, {DirRole});
    });
}
