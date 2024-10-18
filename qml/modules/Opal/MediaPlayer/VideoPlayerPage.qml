//@ This file is part of opal-mediaplayer.
//@ https://github.com/Pretty-SFOS/opal-mediaplayer
//@ SPDX-FileCopyrightText: 2024 Mirian Margiani
//@ SPDX-FileCopyrightText: 2013-2020 Leszek Lesner
//@ SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick 2.6
import Sailfish.Silica 1.0
import QtMultimedia 5.6
import Nemo.KeepAlive 1.2
import Amber.Mpris 1.0
import "private"

Page {
    id: root
    allowedOrientations: Orientation.All

    property string path
    property alias title: titleOverlayItem.title
    property bool autoplay: false
    property bool continueInBackground: false
    property bool enableDarkBackground: true

    property alias mprisAppId: mprisPlayer.identity

    readonly property alias _titleOverlay: titleOverlayItem
    readonly property bool _isPlaying: mediaPlayer.playbackState == MediaPlayer.PlayingState

    function play() {
        videoPoster.play()
    }

    function pause() {
        videoPoster.pause()
    }

    function togglePlay() {
        if (_isPlaying) pause()
        else play()
    }

    onOrientationChanged: video.checkScaleStatus()
    onHeightChanged: video.checkScaleStatus()
    onWidthChanged: video.checkScaleStatus()

    onStatusChanged: {
        if (!continueInBackground && status === PageStatus.Deactivating) {
            pause()
        } else if (autoplay && status === PageStatus.Activating) {
            play()
        }
    }

    onAutoplayChanged: {
        if (autoplay && status === PageStatus.Active) {
            play()
        }
    }

    DisplayBlanking {
        preventBlanking: mediaPlayer.playbackState == MediaPlayer.PlayingState
    }

    Loader {
        z: -1000
        sourceComponent: enableDarkBackground ? backgroundComponent : null
        anchors.fill: parent

        Component {
            id: backgroundComponent

            Rectangle {
                visible: enableDarkBackground
                color: Theme.colorScheme === Theme.LightOnDark ?
                           Qt.darker(Theme.highlightDimmerColor, 4.0) :
                           Qt.darker(Theme.highlightDimmerColor, 8.0)
                opacity: 0.98
            }
        }
    }

    MediaTitleOverlay {
        id: titleOverlayItem
        shown: !autoplay
        title: videoPoster.player.metaData.title || ""
    }

    // -------------------------------------

    property string streamUrl: path
    property string streamTitle: title


    property string videoDuration: {
        if (videoPoster.duration > 3599) return Format.formatDuration(videoPoster.duration, Formatter.DurationLong)
        else return Format.formatDuration(videoPoster.duration, Formatter.DurationShort)
    }
    property string videoPosition: {
        if (videoPoster.position > 3599) return Format.formatDuration(videoPoster.position, Formatter.DurationLong)
        else return Format.formatDuration(videoPoster.position, Formatter.DurationShort)
    }

    property int subtitlesSize: Theme.fontSizeMedium // dataContainer.subtitlesSize
    property bool boldSubtitles: true // dataContainer.boldSubtitles
    property string subtitlesColor: "white" // dataContainer.subtitlesColor
    property bool enableSubtitles: false // dataContainer.enableSubtitles // REQUIRED
    property variant currentVideoSub: []
    property Page dPage
    property bool savedPosition: false
    property string savePositionMsec
    property string subtitleUrl
    property bool subtitleSolid: true // dataContainer.subtitleSolid
    // property bool isPlaylist: dataContainer.isPlaylist
    property bool isNewSource: false
    property bool allowScaling: false
    property bool isRepeat: false

    property alias videoPoster: videoPoster

    // +++
    property bool isLightTheme: Theme.colorScheme === Theme.DarkOnLight


    Component.onCompleted: {
        if (autoplay) {
            //console.debug("[videoPlayer.qml] Autoplay activated for url: " + videoPoster.source);
            play()
            showNavigationIndicator = false;
            mprisPlayer.title = streamTitle;
        }
        console.log("PLAYING", streamUrl, "AUTO", autoplay)
    }

    onStreamUrlChanged: {
        console.log("NEW STREAM URL:", streamUrl)

        errorOverlay.reset()
//        if (errorDetail.visible && errorTxt.visible) { errorDetail.visible = false; errorTxt.visible = false }
        videoPoster.showControls()

        if (streamUrl.toString().match("^file://") || streamUrl.toString().match("^/")) {
            savePositionMsec = "Not Found" //DB.getPosition(streamUrl.toString());
            console.debug("[videoPlayer.qml] streamUrl= " + streamUrl + " savePositionMsec= " + savePositionMsec + " streamUrl.length = " + streamUrl.length);
            if (savePositionMsec !== "Not Found") savedPosition = true;
            else savedPosition = false;
        }
        // if (isPlaylist) mainWindow.curPlaylistIndex = mainWindow.modelPlaylist.getPosition(streamUrl)
        isNewSource = true
    }

    function videoPauseTrigger() {
        // this seems not to work somehow
        if (videoPoster.player.playbackState == MediaPlayer.PlayingState) videoPoster.pause();
        else if (videoPoster.source.toString().length !== 0) videoPoster.play();
        if (videoPoster.controls.opacity === 0.0) videoPoster.toggleControls();

    }

    function toggleAspectRatio() {
        // This switches between different aspect ratio fill modes
        //console.debug("video.fillMode= " + video.fillMode)
        if (video.fillMode == VideoOutput.PreserveAspectFit) video.fillMode = VideoOutput.PreserveAspectCrop
        else video.fillMode = VideoOutput.PreserveAspectFit
        showScaleIndicator.start();
    }

    SilicaFlickable {
        id: flick
        anchors.fill: parent

        // PullDownMenu {
        //     id: pulley
        //
        //     MenuItem {
        //         text: qsTr("Properties")
        //         onClicked: mediaPlayer.loadMetaDataPage("")
        //     }
        //     // MenuItem {
        //     //     text: qsTr("Load Subtitle")
        //     //     onClicked: pageStack.push(openSubsComponent)
        //     // }
        //     // MenuItem {
        //     //     text: qsTr("Playlist")
        //     //     onClicked: mainWindow.firstPage.openPlaylist();
        //     // }
        //     MenuItem {
        //         text: qsTr("Play from last known position")
        //         visible: {
        //             savedPosition
        //         }
        //         onClicked: {
        //             if (mediaPlayer.playbackState != MediaPlayer.PlayingState) videoPoster.play();
        //             mediaPlayer.seek(savePositionMsec)
        //         }
        //     }
        // }

        AnimatedImage {
            id: onlyMusic
            enabled: false

            anchors.centerIn: parent
            source: Qt.resolvedUrl("private/images/audio.gif")
            opacity: enabled ? 0.75 : 0.0
            width: Screen.width / 1.25
            height: width
            playing: true
            visible: opacity > 0

            Behavior on opacity { FadeAnimator {} }
        }

        ProgressCircle {
            id: progressCircle

            enabled: mediaPlayer.status === MediaPlayer.Loading
                     || mediaPlayer.status === MediaPlayer.Buffering
                     || mediaPlayer.status === MediaPlayer.Stalled
            anchors.centerIn: parent
            visible: opacity > 0
            opacity: enabled ? 1.0 : 0.0
            Behavior on opacity { FadeAnimator {} }

            Timer {
                interval: 32
                repeat: true
                running: progressCircle.visible
                onTriggered: {
                    progressCircle.value = (progressCircle.value + 0.005) % 1.0
                }
            }
        }

        Loader {
            id: subTitleLoader
            active: enableSubtitles
            sourceComponent: subItem
            anchors.fill: parent
        }

        Component {
            id: subItem
            SubtitlesItem {
                id: subtitlesText
                anchors { fill: parent; margins: root.inPortrait ? 10 : 50 }
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignBottom
                pixelSize: subtitlesSize
                bold: boldSubtitles
                color: subtitlesColor
                visible: (enableSubtitles) && (currentVideoSub) ? true : false
                isSolid: subtitleSolid
            }
        }

        // Component {
        //     id: openSubsComponent
        //     OpenDialog {
        //         onFileOpen: {
        //             subtitleUrl = path
        //             pageStack.pop()
        //         }
        //     }
        // }

        Rectangle {
            color: Theme.overlayBackgroundColor
            anchors.fill: parent
            opacity: errorOverlay.visible ? Theme.opacityOverlay : 0.0
            z: 1000

            MouseArea {
                anchors.fill: parent
                enabled: errorOverlay.visible
            }

            ErrorOverlay {
                id: errorOverlay
                onVisibleChanged: {
                    if (visible) videoPoster.hideControls()
                }
            }
        }

        Item {
            id: mediaItem
            property bool active: true
            visible: active
            parent: pincher.enabled ? pincher : flick
            anchors.fill: parent

            VideoPoster {
                id: videoPoster
                anchors.fill: parent
                player: mediaPlayer
                autoplay: root.autoplay

                property int mouseX
                property int mouseY

                //duration: videoDuration
                active: mediaItem.active
                source: streamUrl

                onSourceChanged: {
                    position = 0;
                    player.seek(0);
                    //console.debug("Source changed to " + source)
                }

                function play() {
                    playClicked();
                }

                onPlayClicked: {
                    console.debug("Loading source into player")
                    player.source = source;
                    console.debug("Starting playback")
                    player.play();
                    hideControls();

                    if (enableSubtitles) {
                        subTitleLoader.item.getSubtitles(subtitleUrl);
                    }

                    if (mediaPlayer.hasAudio === true &&
                            mediaPlayer.hasVideo === false) {
                        onlyMusic.playing = true
                    }
                }

                // onNextClicked: {
                //     if (isPlaylist && mainWindow.modelPlaylist.isNext()) {
                //         next();
                //     }
                // }
                //
                // onPrevClicked: {
                //     if (isPlaylist && mainWindow.modelPlaylist.isPrev()) {
                //         prev();
                //     }
                // }

                function toggleControls() {
                    if (controls.opacity === 0.0) {
                        showControls()
                    } else {
                        hideControls()
                    }
                }

                function hideControls() {
                    titleOverlayItem.hide()
                    controls.opacity = 0.0
                    // pulley.visible = false
                    root.showNavigationIndicator = false
                }

                function showControls() {
                    titleOverlayItem.show()
                    controls.opacity = 1.0
                    // pulley.visible = true
                    root.showNavigationIndicator = true
                }

                function pause() {
                    mediaPlayer.pause();
                    if (controls.opacity === 0.0) toggleControls();
//                    progressCircle.enabled = false;
                    if (! mediaPlayer.seekable) mediaPlayer.stop();
                    onlyMusic.playing = false
                }

                // function next() {
                //     // reset
                //     dataContainer.streamUrl = ""
                //     dataContainer.streamTitle = ""
                //     videoPoster.player.stop();
                //     // before load new
                //     var nextMedia = mainWindow.modelPlaylist.next()
                //     dataContainer.streamUrl = nextMedia[0]
                //     dataContainer.streamTitle = nextMedia[1]
                //     mediaPlayer.source = streamUrl
                //     videoPauseTrigger();
                //     mediaPlayer.play();
                //     hideControls();
                //     mprisPlayer.title = streamTitle
                // }

                // function prev() {
                //     // reset
                //     dataContainer.streamUrl = ""
                //     dataContainer.streamTitle = ""
                //     videoPoster.player.stop();
                //     // before load new
                //     var prevMedia = mainWindow.modelPlaylist.prev()
                //     dataContainer.streamUrl = prevMedia[0]
                //     dataContainer.streamTitle = prevMedia[1]
                //     mediaPlayer.source = streamUrl
                //     videoPauseTrigger();
                //     mediaPlayer.play();
                //     hideControls();
                //     mprisPlayer.title = streamTitle
                // }

                readonly property int _centerControlHalf: 0.5 * (
                    Theme.iconSizeMedium + 2 * 1.5 * Theme.paddingLarge)
                readonly property int _outerControlSize:
                    Theme.iconSizeMedium + 2 * 0.8 * Theme.paddingLarge
                readonly property int _controlPadding:
                    Theme.paddingLarge
                readonly property int _outerControlThreshold:
                    _centerControlHalf + _controlPadding + _outerControlSize

                function isPlayPauseClick(mouse) {
                    var middleX = width / 2
                    var middleY = height / 2

                    return (
                        (mouse.x >= middleX - _centerControlHalf &&
                         mouse.x <= middleX + _centerControlHalf)
                    &&
                        (mouse.y >= middleY - _centerControlHalf &&
                         mouse.y <= middleY + _centerControlHalf)
                    )
                }

                function isForwardClick(mouse) {
                    var middleX = width / 2
                    var middleY = height / 2


                    return (
                        (mouse.x > middleX + _centerControlHalf &&
                         mouse.x < middleX + _outerControlThreshold)
                    &&
                        (mouse.y >= middleY - _centerControlHalf &&
                         mouse.y <= middleY + _centerControlHalf)
                    )
                }

                function isRewindClick(mouse) {
                    var middleX = width / 2
                    var middleY = height / 2

                    return (
                        (mouse.x < middleX - _centerControlHalf &&
                         mouse.x > middleX - _outerControlThreshold)
                    &&
                        (mouse.y >= middleY - _centerControlHalf &&
                         mouse.y <= middleY + _centerControlHalf)
                    )

                }

                onClicked: {
                    if (isPlayPauseClick(mouse)) {
                        togglePlay()
                    } else if (isForwardClick(mouse)) {
                        ffwd(10)
                    } else if (isRewindClick(mouse)) {
                        rew(5)
                    } else {
                        toggleControls()
                    }
                }

                onPositionChanged: {
                    if (enableSubtitles && currentVideoSub) {
                        subTitleLoader.item.checkSubtitles()
                    }
                }
            }
        }
    }

    PinchArea {
        id: pincher
        enabled: allowScaling && /*!pulley.visible &&*/ !errorBox.visible
        visible: enabled
        anchors.fill: parent
        pinch.target: video
        pinch.minimumScale: 1
        pinch.maximumScale: 1 + (((root.width/root.height) - (video.sourceRect.width/video.sourceRect.height)) / (video.sourceRect.width/video.sourceRect.height))
        pinch.dragAxis: Pinch.XAndYAxis
        property bool pinchIn: false
        onPinchUpdated: {
            if (pinch.previousScale < pinch.scale) {
                pinchIn = true
            }
            else if (pinch.previousScale > pinch.scale) {
                pinchIn = false
            }
        }
        onPinchFinished: {
            if (pinchIn) {
                video.fillMode = VideoOutput.PreserveAspectCrop
            }
            else {
                video.fillMode = VideoOutput.PreserveAspectFit
            }
            showScaleIndicator.start();
        }
    }

    Jupii {
        id: jupii
    }

        VideoOutput {
            id: video
            z: -1000
            anchors.fill: parent
            transformOrigin: Item.Center

            function checkScaleStatus() {
                if ((root.width/root.height) > sourceRect.width/sourceRect.height) allowScaling = true;
                console.log(root.width/root.height + " - " + sourceRect.width/sourceRect.height);
            }

            onFillModeChanged: {
                if (fillMode === VideoOutput.PreserveAspectCrop) scale = 1 + (((root.width/root.height) - (sourceRect.width/sourceRect.height)) / (sourceRect.width/sourceRect.height))
                else scale=1
            }

            source: Mplayer {
                id: mediaPlayer
                dataContainer: root
                streamTitle: root.streamTitle
                streamUrl: root.streamUrl
                isPlaylist: false // root.isPlaylist
                isLiveStream: false // root.isLiveStream
                onPlaybackStateChanged: {
                    if (playbackState == MediaPlayer.PlayingState) {
                        if (onlyMusic.enabled) onlyMusic.playing = true
                        mprisPlayer.playbackStatus = Mpris.Playing
                        video.checkScaleStatus()
                    }
                    else  {
                        if (onlyMusic.enabled) onlyMusic.playing = false
                        mprisPlayer.playbackStatus = Mpris.Paused
                    }
                }
                onDurationChanged: {
                    //console.debug("Duration(msec): " + duration);
                    videoPoster.duration = (duration/1000)

                    if (hasAudio === true && hasVideo === false) {
                        onlyMusic.enabled = true
                    } else {
                        onlyMusic.enabled = false
                    }
                }
                onStatusChanged: {
                    //errorTxt.visible = false     // DEBUG: Always show errors for now
                    //errorDetail.visible = false
                    // console.debug("[videoPlayer.qml]: mediaPlayer.status: " + mediaPlayer.status + " isPlaylist:" + isPlaylist)
//                    if (mediaPlayer.status === MediaPlayer.Loading || mediaPlayer.status === MediaPlayer.Buffering || mediaPlayer.status === MediaPlayer.Stalled) progressCircle.enabled = true;
                    /*else*/ if (mediaPlayer.status === MediaPlayer.EndOfMedia) {
                        videoPoster.showControls();
                        // if (isPlaylist && mainWindow.modelPlaylist.isNext()) {
                        //     videoPoster.next();
                        // }
                    }
                    else  {
//                        progressCircle.enabled = false;
                        /*if (!isPlaylist) */loadMetaDataPage("inBackground");
                        // else loadPlaylistPage();
                    }
                    if (metaData.title) {
                        //console.debug("MetaData.title = " + metaData.title)
                        if (dPage) dPage.title = metaData.title
                        mprisPlayer.title = metaData.title
                    }
                }

                onHasVideoChanged: {
//                    if (hasAudio && !hasVideo) {
//                        onlyMusic.playing = Qt.binding(function(){
//                            return mediaPlayer.isPlaying
//                        })
//                    }
                }

                onError: {
                    if (error === MediaPlayer.NoError) {
                        return
                    }

                    // we don't want to risk crashes by trying any further
                    console.error("[Opal.MediaPlayer] video playback failed:", error, errorString)
                    stop()

                    errorOverlay.show(error, errorString)
                }

                onStopped: {
                    if (isRepeat) {
                        play();
                    }
                }
            }

            visible: mediaPlayer.status >= MediaPlayer.Loaded && mediaPlayer.status <= MediaPlayer.EndOfMedia
            width: parent.width
            height: parent.height
            anchors.centerIn: root
        }

    Item {
        id: scaleIndicator

        anchors.horizontalCenter: root.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 4 * Theme.paddingLarge
        opacity: 0
        property alias fadeOut: fadeOut

        NumberAnimation on opacity {
            id: fadeOut
            to: 0
            duration: 400;
            easing.type: Easing.InOutCubic
        }

        Rectangle {
            width: scaleLblIndicator.width + 2 * Theme.paddingMedium
            height: scaleLblIndicator.height + 2 * Theme.paddingMedium
            color: isLightTheme? "white" : "black"
            opacity: 0.4
            anchors.centerIn: parent
            radius: 2
        }
        Label {
            id: scaleLblIndicator
            font.pixelSize: Theme.fontSizeSmall
            anchors.centerIn: parent
            text: (video.fillMode === VideoOutput.PreserveAspectCrop) ?
                qsTranslate("Opal.MediaPlayer", "Zoomed to fit screen") :
                qsTranslate("Opal.MediaPlayer", "Original")
            color: Theme.primaryColor
        }
    }

    Timer {
        id: showScaleIndicator
        interval: 1000
        property int count: 0
        triggeredOnStart: true
        repeat: true
        onTriggered: {
            ++count
            if (count == 2) {
                scaleIndicator.fadeOut.start();
                count = 0;
                stop();
            }
            else {
                scaleIndicator.opacity = 1.0
            }
        }
    }

    Keys.onPressed: {
        if (event.key === Qt.Key_Space) videoPauseTrigger();
        if (event.key === Qt.Key_Left && mediaPlayer.seekable) {
            mediaPlayer.seek(mediaPlayer.position - 5000)
        }
        if (event.key === Qt.Key_Right && mediaPlayer.seekable) {
            mediaPlayer.seek(mediaPlayer.position + 10000)
        }
    }

    MprisConnector {
        id: mprisPlayer

        onPauseRequested: {
            videoPoster.pause();
        }
        onPlayRequested: {
            videoPoster.play();
        }
        onPlayPauseRequested: {
            root.videoPauseTrigger();
        }
        onStopRequested: {
            videoPoster.player.stop();
        }
        // onNextRequested: {
        //     videoPoster.next();
        // }
        // onPreviousRequested: {
        //     videoPoster.prev();
        // }
        onSeekRequested: {
            mediaPlayer.seek(offset);
        }
    }
}
