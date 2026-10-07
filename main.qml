import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import QtWebSockets

import org.qfield
import org.qgis
import Theme

Item {
  id: plugin

  property var mainWindow: iface.mainWindow()
  property var mapCanvas: iface.mapCanvas()
  property var pointHandler: iface.findItemByObjectName("pointHandler")

  property var deviceIds: []
  property var deviceDetails: []

  Settings {
    id: settings
    category: "traccar"

    property string url: "";
    property string accountEmail: "";
    property string accountPassword: "";
  }

  Repeater {
    parent: mapCanvas
    model: deviceIds
    
    delegate: Rectangle {
      id: deviceMarker

      property bool isOnline: deviceDetails[modelData]["status"] === "online"
      property color markerColor: isOnline ? "#7b58c3" : "#bbbbbb"
      property color accuracyColor: isOnline ? "#447b58c3" : "#44bbbbbb"

      CoordinateTransformer {
        id: coordinateTransformer
        transformContext: qgisProject ? qgisProject.transformContext : CoordinateReferenceSystemUtils.emptyTransformContext()
        sourcePosition: {
          deviceDetails[modelData]["position"] !== undefined ? deviceDetails[modelData]["position"] : GeometryUtils.emptyPoint()
        }
        sourceCrs: CoordinateReferenceSystemUtils.wgs84Crs()
        destinationCrs: mapCanvas.mapSettings.destinationCrs
      }

      Quick3DGeometryConfiguration {
        id: device3DConfiguration
        color: "#7b58c3"
        lineWidth: 10
        altitudeClamping: Quick3DGeometry.Absolute
        crs: qgisProject.crs
        wkt: {
          const wkt = "POINT (" + coordinateTransformer.projectedPosition.x + " " + coordinateTransformer.projectedPosition.y + " " + coordinateTransformer.projectedPosition.z + ")";
          return wkt;
        }

        Component.onCompleted: {
          iface.addItemToMapCanvas3D(device3DConfiguration)
        }
      }

      MapToScreen {
        id: mapToScreen
        mapSettings: mapCanvas.mapSettings
        mapPoint: coordinateTransformer.projectedPosition
      }

      visible: deviceDetails[modelData]["position"] !== undefined

      width: 32
      height: width
      radius: width / 2

      x: mapToScreen.screenPoint.x - width / 2
      y: mapToScreen.screenPoint.y - height + 4

      color: "transparent"

      Rectangle {
        anchors.centerIn: parent
        width: deviceDetails[modelData]["accuracy"] / mapCanvas.mapSettings.mapUnitsPerPoint
        height: width
        radius: width / 2

        color: deviceMarker.accuracyColor
      }

      Rectangle {
        anchors.centerIn: parent
        width: deviceMarker.width
        height: deviceMarker.width
        radius: deviceMarker.width / 2
        color: "#ffffff"

        border.color: deviceMarker.markerColor
        border.width: 2

        ParameterizedImage {
          anchors.centerIn: parent
          source: UrlUtils.toLocalFile(Qt.resolvedUrl('marker.svg'));
          width: deviceMarker.width - 8
          height: deviceMarker.width - 8
          fillColor: deviceMarker.markerColor
        }
        
      
        Rectangle {
          anchors.bottom: parent.top
          anchors.horizontalCenter: parent.horizontalCenter
          width: markerLabel.contentWidth + 4
          height: markerLabel.contentHeight + 2
          radius: 2

          Label {
            id: markerLabel
            anchors.centerIn: parent
            text: deviceDetails[modelData]["name"] || "XXX"
            font.capitalization: Font.AllUppercase
            font.pointSize: Theme.tinyFont.pointSize
            font.bold: true
            color: deviceMarker.markerColor
          }
        }
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: 2000
    repeat: false

    onTriggered: {
      refreshDeviceLocations();
    }
  }

  function refreshDeviceLocations() {
    getDevicePositions();
  }

  function getDevicePosition(deviceId) {
    console.log(`Getting device ${deviceId} position...`);
    let request = iface.createHttpRequest();
    request.onreadystatechange = () => {
      if (request.readyState === XMLHttpRequest.DONE) {
        if (request.status === 200) {
          let dds = deviceDetails;
          const json = JSON.parse(request.responseText);
          if (deviceIds.indexOf(json["deviceId"]) >= 0) {
            if (json["fixTime"] !== undefined && dds[deviceId]["lastUpdate"] !== json["fixTime"]) {
              const isOnline = ((Date.now() - (new Date(json["fixTime"])).getTime()) / 1000) < 600;
              dds[deviceId]["status"] =  isOnline ? "online" : "unknown";
              dds[deviceId]["lastUpdate"] = json["fixTime"];
            }
            if (json["valid"] === true) {
              dds[deviceId]["position"] = GeometryUtils.point(json["longitude"], json["latitude"], json["altitude"]);
              dds[deviceId]["accuracy"] = json["accuracy"];
            } else {
              dds[deviceId]["position"] = undefined;
              dds[deviceId]["accuracy"] = 0;
            }
          }
          deviceDetails = dds;
          deviceDetailsChanged();
        }
      }
    };

    const url = `${settings.url}/positions/${deviceId}`;
    request.open("GET", url);
    request.send();
  }

  function getDevicePositions() {
    console.log(`Getting all device positions...`);
    let request = iface.createHttpRequest();
    request.onreadystatechange = () => {
      if (request.readyState === XMLHttpRequest.DONE) {
        if (request.status === 200) {
          let dds = deviceDetails;
          const json = JSON.parse(request.responseText);
          for (const position of json) {
            if (deviceIds.indexOf(position["deviceId"]) >= 0) {
              if (position["fixTime"] !== undefined && dds[position["deviceId"]]["lastUpdate"] !== position["fixTime"]) {
                const isOnline = ((Date.now() - (new Date(position["fixTime"])).getTime()) / 1000) < 600;
                dds[position["deviceId"]]["status"] =  isOnline ? "online" : "unknown";
                dds[position["deviceId"]]["lastUpdate"] = position["fixTime"];
              }
              if (position["valid"] === true) {
                dds[position["deviceId"]]["position"] = GeometryUtils.point(position["longitude"], position["latitude"], position["altitude"]);
                dds[position["deviceId"]]["accuracy"] = position["accuracy"];
              } else {
                dds[position["deviceId"]]["position"] = undefined;
                dds[json["deviceId"]]["accuracy"] = json["accuracy"];
              }
            }
          }
          deviceDetails = dds;
          deviceDetailsChanged();
          refreshTimer.restart();
        }
      }
    };

    const url = `${settings.url}/positions`;
    request.open("GET", url);
    request.send();
  }

  function getDevices() {
    console.log('Getting devices...');
    let request = iface.createHttpRequest();
    request.onreadystatechange = () => {
      if (request.readyState === XMLHttpRequest.DONE) {
        let dis = [];
        let dds = [];
        if (request.status === 200) {
          const json = JSON.parse(request.responseText);
          for (const device of json) {
            if (device["id"] !== undefined) {
              dis.push(device["id"])
              dds[device["id"]] = [];
              dds[device["id"]]["name"] = device["name"];
              dds[device["id"]]["status"] = device["status"];
              dds[device["id"]]["lastUpdate"] = device["lastUpdate"];
              dds[device["id"]]["position"] = undefined;
              dds[device["id"]]["accuracy"] = 0;
            }
          }
        } else {
          mainWindow.displayToast(qsTr(`Getting devices failed`));
        }
        deviceDetails = dds;
        deviceIds = dis;
        deviceIdsChanged();

        if (deviceIds.length > 0) {
          refreshDeviceLocations()
        }
      }
    };

    const url = `${settings.url}/devices`;
    request.open("GET", url);
    request.send();
  }

  function createSession() {
    console.log('Creating session...');
    let request = iface.createHttpRequest();
    request.onreadystatechange = () => {
      if (request.readyState === XMLHttpRequest.DONE) {
        if (request.status === 200) {
          /// login succeeded
          getDevices();
          mainWindow.displayToast(qsTr(`Connected to the Traccar server`));
        } else {
          mainWindow.displayToast(qsTr(`Connection to the Traccar server failed, check your credentials`));
        }
      }
    };

    const url = `${settings.url}/session`;
    request.open("POST", url);
    request.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
    request.send(`email=${settings.accountEmail}&password=${settings.accountPassword}`);
  }

  function reset() {
    refreshTimer.stop();
    deviceIds = [];
    deviceDetails = [];
  }

  function configure() {
    settingsDialog.open();
  }

  Dialog {
    id: settingsDialog
    parent: mainWindow.contentItem
    visible: false
    modal: true
    font: Theme.defaultFont
    standardButtons: Dialog.Ok | Dialog.Cancel
    title: qsTr("Traccar Settings")
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: mainWindow.width * 0.8

    onAboutToShow: {
      urlField.text = settings.url;
      accountEmailField.text = settings.accountEmail;
      accountPasswordField.text = settings.accountPassword;
    }

    ColumnLayout {
      width: parent.width
      spacing: 10

      Label {
        text: qsTr("Traccar endpoint URL")
        font: Theme.defaultFont
      }

      TextField {
        id: urlField
        Layout.fillWidth: true
        font: Theme.defaultFont
      }

      Label {
        text: qsTr("Traccar account email")
        font: Theme.defaultFont
      }

      TextField {
        id: accountEmailField
        Layout.fillWidth: true
        font: Theme.defaultFont
      }

      Label {
        text: qsTr("Traccar account password")
        font: Theme.defaultFont
      }

      TextField {
        id: accountPasswordField
        Layout.fillWidth: true
        font: Theme.defaultFont
        echoMode: TextInput.Password
        passwordMaskDelay: 500
      }
    }

    onAccepted: {
      const accountChanged = settings.url !== urlField.text || settings.accountEmail !== accountEmailField.text || settings.accountPassword !== accountPasswordField.text;

      settings.url = urlField.text
      settings.accountEmail = accountEmailField.text
      settings.accountPassword = accountPasswordField.text

      mainWindow.displayToast(qsTr(`Settings stored`));

      if (accountChanged && settings.url != '' && settings.accountEmail != '' && settings.accountPassword != '') {
        reset();
        createSession();
      }
    }
  }

  Component.onCompleted: {
    if (settings.url != '' && settings.accountEmail != '' && settings.accountPassword != '') {
      createSession();
    }
    pointHandler.registerHandler("traccar", (point, type, interactionType) => {
                                   if (interactionType === "clicked") {
                                     const wgs84 = CoordinateReferenceSystemUtils.wgs84Crs();
                                     for (const deviceId of deviceIds) {
                                       if (deviceDetails[deviceId]["position"] !== undefined) {
                                         const projectedPoint = GeometryUtils.reprojectPoint(deviceDetails[deviceId]["position"], wgs84, mapCanvas.mapSettings.destinationCrs);
                                         const screenPoint = mapCanvas.mapSettings.coordinateToScreen(projectedPoint);
                                         if (Math.abs(point.x - screenPoint.x) < 32 && Math.abs(point.y - screenPoint.y) < 32) {
                                           const diffMs = Date.now() - (new Date(deviceDetails[deviceId]["lastUpdate"]).getTime());
                                           if (diffMs >= 3600000) {
                                             const diffHours = Math.floor(diffMs / 3600000);
                                             mainWindow.displayToast(`Traccar device name ${deviceDetails[deviceId]["name"]}\nLast updated ${diffHours} hour(s) ago`);
                                           } else if (diffMs >= 60000) {
                                             const diffMinutes = Math.floor(diffMs / 60000);
                                             mainWindow.displayToast(`Traccar device name ${deviceDetails[deviceId]["name"]}\nLast updated ${diffMinutes} minutes(s) ago`);
                                           } else {
                                             const diffSeconds = Math.floor(diffMs / 1000);
                                             mainWindow.displayToast(`Traccar device name ${deviceDetails[deviceId]["name"]}\nLast updated ${diffSeconds} second(s) ago`);
                                           }
                                           return true;
                                         }
                                       }
                                     }
                                   }
                                   return false;
    });
  }

  Component.onDestruction: {
    pointHandler.deregisterHandler("traccar");
  }
}
