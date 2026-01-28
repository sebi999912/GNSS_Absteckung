import QtQuick // QML-Grundmodule
import QtQuick.Controls // Standard-Controls für Buttons und Labels

import org.qfield // QField-spezifische Interfaces
import org.qgis // QGIS-Klassen (Geometrie, CRS, Transformation)
import Theme // QField-Themefarben

Item { // Wurzel-Element des Plugins
  id: plugin // Eindeutige ID für das Plugin-Item

  property var mainWindow: iface.mainWindow() // Referenz auf das Hauptfenster von QField
  property var positionSource: iface.findItemByObjectName('positionSource') // Zugriff auf die GNSS-Position
  property var mapCanvas: iface.mapCanvas() // Zugriff auf die Kartenansicht

  property var targetFeature: null // Aktuell ausgewähltes Feature für die Absteckung
  property string targetIdText: qsTr('Kein Punkt gewählt') // Textanzeige für die Objekt-ID
  property string northSouthText: qsTr('-') // Textanzeige für Nord-/Südrichtung
  property string eastWestText: qsTr('-') // Textanzeige für Ost-/Westrichtung

  property var wgs84Crs: QgsCoordinateReferenceSystem.fromEpsgId(4326) // WGS84 für GNSS-Lat/Lon
  property var projectCrs: QgsProject.instance().crs() // Projekt-CRS für metrische Berechnungen
  property var crsTransform: QgsCoordinateTransform(wgs84Crs, projectCrs, QgsProject.instance()) // Transformation nach Projekt-CRS

  Component.onCompleted: { // Initialisierung beim Laden des Plugins
    iface.addItemToPluginsToolbar(pluginButton) // Button in die Plugin-Toolbar hinzufügen
  }

  function updateTargetFromSelection() { // Aktualisiert Zielpunkt aus der Layer-Selektion
    let layer = iface.activeLayer() // Aktuellen aktiven Layer holen
    if (!layer || !layer.selectedFeatureCount || layer.selectedFeatureCount === 0) { // Prüfen ob Selection vorhanden ist
      targetFeature = null // Zielpunkt zurücksetzen
      targetIdText = qsTr('Kein Punkt gewählt') // Hinweistext für fehlende Auswahl
      northSouthText = qsTr('-') // Absteckwerte leeren
      eastWestText = qsTr('-') // Absteckwerte leeren
      return // Funktion beenden
    }

    let features = layer.selectedFeatures() // Ausgewählte Features holen
    if (!features || features.length === 0) { // Sicherheitscheck, falls keine Features geliefert werden
      targetFeature = null // Zielpunkt zurücksetzen
      targetIdText = qsTr('Kein Punkt gewählt') // Hinweistext setzen
      northSouthText = qsTr('-') // Absteckwerte leeren
      eastWestText = qsTr('-') // Absteckwerte leeren
      return // Funktion beenden
    }

    targetFeature = features[0] // Erstes selektiertes Feature verwenden
    targetIdText = qsTr('Objekt-ID: ') + targetFeature.id() // Objekt-ID anzeigen
    updateStakeoutValues() // Absteckwerte anhand der aktuellen Position berechnen
  }

  function updateStakeoutValues() { // Berechnet Nord/Süd und Ost/West Differenzen
    if (!targetFeature) { // Ohne Zielpunkt keine Berechnung
      northSouthText = qsTr('-') // Absteckwerte leeren
      eastWestText = qsTr('-') // Absteckwerte leeren
      return // Funktion beenden
    }

    let position = positionSource.positionInformation // GNSS-Positionsinfo lesen
    if (!positionSource.active || !position.latitudeValid || !position.longitudeValid) { // GNSS prüfen
      northSouthText = qsTr('GNSS nicht verfügbar') // Hinweistext für fehlende GNSS-Daten
      eastWestText = qsTr('GNSS nicht verfügbar') // Hinweistext für fehlende GNSS-Daten
      return // Funktion beenden
    }

    let targetGeom = targetFeature.geometry() // Geometrie des Ziel-Features holen
    let targetPoint = targetGeom.asPoint() // Punktgeometrie extrahieren

    let currentPointWgs84 = QgsPointXY(position.longitude, position.latitude) // GNSS-Punkt in WGS84
    let currentPoint = crsTransform.transform(currentPointWgs84) // GNSS-Punkt ins Projekt-CRS transformieren

    let deltaEast = targetPoint.x - currentPoint.x // Ost/West-Differenz (X)
    let deltaNorth = targetPoint.y - currentPoint.y // Nord/Süd-Differenz (Y)

    let eastWestLabel = deltaEast >= 0 ? qsTr('Ost') : qsTr('West') // Richtung Ost/West bestimmen
    let northSouthLabel = deltaNorth >= 0 ? qsTr('Nord') : qsTr('Süd') // Richtung Nord/Süd bestimmen

    let eastWestMeters = Math.abs(deltaEast).toFixed(2) // Betrag der Ost/West-Distanz in Metern
    let northSouthMeters = Math.abs(deltaNorth).toFixed(2) // Betrag der Nord/Süd-Distanz in Metern

    northSouthText = northSouthLabel + qsTr(': ') + northSouthMeters + qsTr(' m') // Formatierten Nord/Süd-Text setzen
    eastWestText = eastWestLabel + qsTr(': ') + eastWestMeters + qsTr(' m') // Formatierten Ost/West-Text setzen
  }

  Connections { // Verbindung zu Layer-Selection
    target: iface // QField-Interface als Signalquelle
    function onActiveLayerChanged() { // Wenn aktiver Layer wechselt
      updateTargetFromSelection() // Auswahl neu lesen
    }
  }

  Connections { // Verbindung zur aktiven Layer-Selektion
    target: iface.activeLayer() // Aktiver Layer als Signalquelle
    function onSelectionChanged() { // Wenn Auswahl sich ändert
      updateTargetFromSelection() // Auswahl neu lesen
    }
  }

  Timer { // Timer für regelmäßige GNSS-Aktualisierung
    id: positionTimer // ID für den Timer
    interval: 1000 // Jede Sekunde aktualisieren
    running: true // Timer starten
    repeat: true // Wiederholen
    onTriggered: updateStakeoutValues() // Absteckwerte aktualisieren
  }

  QfToolButton { // Button für das Aktivieren der Absteck-Ansicht
    id: pluginButton // ID für den Button
    iconSource: 'icon.svg' // Plugin-Icon
    iconColor: Theme.mainColor // Iconfarbe
    bgcolor: Theme.darkGray // Hintergrundfarbe des Buttons
    round: true // Runden Button zeichnen

    onClicked: { // Klick-Handler
      stakeoutPanel.visible = !stakeoutPanel.visible // Panel ein-/ausblenden
      updateTargetFromSelection() // Auswahl neu berechnen
    }
  }

  Rectangle { // Panel im unteren Bereich
    id: stakeoutPanel // ID für das Panel
    visible: false // Standardmäßig ausgeblendet
    anchors.left: parent.left // Links am Plugin-Root ausrichten
    anchors.right: parent.right // Rechts am Plugin-Root ausrichten
    anchors.bottom: parent.bottom // Unten am Plugin-Root ausrichten
    height: 140 // Höhe des Panels
    color: Theme.darkGray // Hintergrundfarbe
    opacity: 0.92 // Leicht transparente Darstellung

    Column { // Vertikale Anordnung der Texte
      anchors.fill: parent // Column füllt das Panel
      anchors.margins: 12 // Innenabstand
      spacing: 6 // Abstand zwischen den Zeilen

      Label { // Label für die Überschrift
        text: qsTr('Absteckung') // Überschriftstext
        color: Theme.lightGray // Textfarbe
        font.bold: true // Fettschrift
        font.pixelSize: 18 // Schriftgröße
      }

      Label { // Label für die Objekt-ID
        text: targetIdText // Objekt-ID Text
        color: Theme.lightGray // Textfarbe
        font.pixelSize: 14 // Schriftgröße
      }

      Label { // Label für Nord/Süd
        text: northSouthText // Nord/Süd-Text
        color: Theme.lightGray // Textfarbe
        font.pixelSize: 16 // Schriftgröße
      }

      Label { // Label für Ost/West
        text: eastWestText // Ost/West-Text
        color: Theme.lightGray // Textfarbe
        font.pixelSize: 16 // Schriftgröße
      }
    }
  }
}
