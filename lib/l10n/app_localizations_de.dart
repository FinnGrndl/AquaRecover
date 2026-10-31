// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'AquaRecover';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get ok => 'OK';

  @override
  String get done => 'Fertig';

  @override
  String get apply => 'Anwenden';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get delete => 'Löschen';

  @override
  String get share => 'Teilen';

  @override
  String get undo => 'Rückgängig';

  @override
  String get redo => 'Wiederholen';

  @override
  String get change => 'Ändern';

  @override
  String get manage => 'Verwalten';

  @override
  String get optional => 'Optional';

  @override
  String get preview => 'Vorschau';

  @override
  String get original => 'Original';

  @override
  String get selected => 'Ausgewählt';

  @override
  String get status => 'Status';

  @override
  String get libraryBack => 'Mediathek';

  @override
  String get exportAction => 'Exportieren';

  @override
  String get exportTitle => 'Export';

  @override
  String get exportAll => 'Alle exportieren';

  @override
  String get exportingEllipsis => 'Wird exportiert …';

  @override
  String get exportingShort => 'Exportiert …';

  @override
  String get licenses => 'Lizenzen';

  @override
  String get movies => 'Filme';

  @override
  String get diveLogbook => 'Tauchlogbuch';

  @override
  String get localExports => 'Lokale Exporte';

  @override
  String get aboutApp => 'Über AquaRecover';

  @override
  String get quickTour => 'Kurze Tour';

  @override
  String aboutBody(String version) {
    return 'Version $version\\n\\nUnterwasser-Farbkorrektur direkt auf dem Gerät für Fotos, RAW-Bilder, Videos, LUTs und lokale Exporte.';
  }

  @override
  String get destinationPhotos => 'Fotos';

  @override
  String get destinationFiles => 'Dateien';

  @override
  String get presetNone => 'Ohne';

  @override
  String get presetAuto => 'Auto';

  @override
  String get presetNatural => 'Natürlich';

  @override
  String get presetVivid => 'Lebhaftes Riff';

  @override
  String get presetDeep => 'Tieftauchgang';

  @override
  String get presetMacro => 'Makro';

  @override
  String get presetShallow => 'Flachwasser';

  @override
  String get presetGreenWater => 'Grünes Wasser';

  @override
  String get presetRedFilter => 'Rotfilter';

  @override
  String get presetArtificialLight => 'Kunstlicht';

  @override
  String get presetNoneHelp => 'Lässt das Bild unverändert.';

  @override
  String get presetAutoHelp =>
      'Ausgewogene Korrektur mit einem Tippen für typisches blaugrünes Wasser.';

  @override
  String get presetNaturalHelp =>
      'Weniger Kontrast und Sättigung für einen dokumentarischen Look.';

  @override
  String get presetVividHelp => 'Mehr Kontrast und Farbe für Riffszenen.';

  @override
  String get presetDeepHelp => 'Stärkere Rotkorrektur für tiefere Tauchgänge.';

  @override
  String get presetMacroHelp => 'Mehr lokale Details für nahe Motive.';

  @override
  String get presetShallowHelp =>
      'Sanfte Korrektur fürs Schnorcheln und sonniges Flachwasser.';

  @override
  String get presetGreenWaterHelp =>
      'Gleicht grünes, planktonreiches Wasser aus, ohne zu viel Magenta.';

  @override
  String get presetRedFilterHelp =>
      'Gleicht Aufnahmen mit rotem Tauchfilter aus.';

  @override
  String get presetArtificialLightHelp =>
      'Schützt Lichter vor Lampen und Blitzen.';

  @override
  String get mediaKindPhoto => 'Foto';

  @override
  String get mediaKindRawPhoto => 'RAW-Foto';

  @override
  String get mediaKindVideo => 'Video';

  @override
  String get mediaKindRawVideo => 'RAW-Video';

  @override
  String get jobStatusReady => 'Bereit';

  @override
  String get jobStatusProcessing => 'In Bearbeitung';

  @override
  String get jobStatusComplete => 'Fertig';

  @override
  String get jobStatusFailed => 'Fehlgeschlagen';

  @override
  String get beforeAfterSideBySide => 'Nebeneinander';

  @override
  String get beforeAfterSplit => 'Geteilt';

  @override
  String get exportPresetSocial => 'Social';

  @override
  String get exportPresetArchive => 'Archiv';

  @override
  String get exportPresetProEdit => 'Profi';

  @override
  String get lutNone => 'Ohne';

  @override
  String get lutCoralWarm => 'Korallenwarm';

  @override
  String get lutBlueWater => 'Blaues Wasser';

  @override
  String get lutGreenWater => 'Grünes Wasser';

  @override
  String get lutCustomCube => 'Eigene .cube-Datei';

  @override
  String get cropOriginal => 'Original';

  @override
  String get cropFree => 'Frei';

  @override
  String get cropSquare => 'Quadrat';

  @override
  String get workflowImport => 'Importieren';

  @override
  String get workflowEdit => 'Bearbeiten';

  @override
  String get workflowExport => 'Exportieren';

  @override
  String get toolPresets => 'Vorgaben';

  @override
  String get toolAdjust => 'Anpassen';

  @override
  String get toolCrop => 'Zuschneiden';

  @override
  String get toolColor => 'Farbe';

  @override
  String get toolDetails => 'Details';

  @override
  String get toolLut => 'LUT';

  @override
  String get toolVideo => 'Video';

  @override
  String get toolPresetsSubtitle => 'Ausgangsprofil und Stärke';

  @override
  String get toolAdjustSubtitle => 'Alle Bildanpassungen';

  @override
  String get toolCropSubtitle => 'Zuschneiden, drehen und spiegeln';

  @override
  String get toolColorSubtitle => 'Wasserstich und Farbbalance';

  @override
  String get toolDetailsSubtitle => 'Dunst, Klarheit und Schärfe';

  @override
  String get toolLutSubtitle => 'Look-up-Tabelle und Vignette';

  @override
  String get toolVideoSubtitle => 'Vorschaubild und Trimmen';

  @override
  String get adjRecovery => 'Wasser-Korrektur';

  @override
  String get adjRecoveryHelp =>
      'Steuert nur die Korrektur des Unterwasser-Farbstichs. Sie verstärkt die Farbwiederherstellung und die lokale Neutralisierung, ändert aber nicht Belichtung, Kontrast, Sättigung oder Schärfe.';

  @override
  String get adjContrastStretch => 'Kontrast spreizen';

  @override
  String get adjContrastStretchHelp =>
      'Spreizt den gemessenen Bereich von dunkel bis hell. Hohe Werte machen trübe Szenen knackiger, können aber Details beschneiden.';

  @override
  String get adjContrast => 'Kontrast';

  @override
  String get adjContrastHelp =>
      'Ändert die Trennung der Mitteltöne, ohne die Unterwasser-Farbkorrektur neu zu berechnen.';

  @override
  String get adjGamma => 'Gamma';

  @override
  String get adjGammaHelp =>
      'Verschiebt die Helligkeit der Mitteltöne, während Schwarz- und Weißpunkt weitgehend bleiben.';

  @override
  String get adjBrightness => 'Helligkeit';

  @override
  String get adjBrightnessHelp =>
      'Fügt nach der Hauptkorrektur gleichmäßig Licht hinzu oder nimmt es weg.';

  @override
  String get adjExposure => 'Belichtung';

  @override
  String get adjExposureHelp =>
      'Skaliert die Helligkeit wie eine kleine Belichtungskorrektur. Tiefen und Lichter ändern sich gemeinsam.';

  @override
  String get adjHighlights => 'Lichter';

  @override
  String get adjHighlightsHelp =>
      'Hellt die hellsten Bereiche auf oder dunkelt sie ab und schont den übrigen Tonwertbereich.';

  @override
  String get adjShadows => 'Tiefen';

  @override
  String get adjShadowsHelp =>
      'Hellt dunkle Bereiche auf oder vertieft sie, ohne die Helligkeit des ganzen Bilds zu ändern.';

  @override
  String get adjBlackPoint => 'Schwarzpunkt';

  @override
  String get adjBlackPointHelp =>
      'Vertieft die dunkelsten Töne. Erhöhe ihn vorsichtig, damit keine Details in den Tiefen verloren gehen.';

  @override
  String get adjTemperature => 'Temperatur';

  @override
  String get adjTemperatureHelp =>
      'Feinabstimmung zwischen warm und kühl nach der Wasser-Korrektur. Die Weißabgleich-Pipette setzt sie mit einem Tippen.';

  @override
  String get adjTint => 'Tönung';

  @override
  String get adjTintHelp =>
      'Feinabstimmung zwischen Grün und Magenta. Positive Werte entfernen einen verbliebenen Grünstich.';

  @override
  String get adjRedRecovery => 'Rotkorrektur';

  @override
  String get adjRedRecoveryHelp =>
      'Holt warme Farben zurück, die das Wasser schluckt. Das Ergebnis wird mit der Wasser-Korrektur multipliziert, beide Regler wirken also zusammen.';

  @override
  String get adjAutoWhiteBalance => 'Auto-Weißabgleich';

  @override
  String get adjAutoWhiteBalanceHelp =>
      'Gleicht die mittleren Rot-, Grün- und Blauwerte in sicheren Grenzen an. Verringere ihn, wenn gewolltes Licht warm oder kühl bleiben soll.';

  @override
  String get adjSaturation => 'Sättigung';

  @override
  String get adjSaturationHelp =>
      'Ändert die Intensität aller Farben gleichmäßig. Hohe Werte verstärken Farbrauschen und Wasserstich.';

  @override
  String get adjVibrance => 'Lebendigkeit';

  @override
  String get adjVibranceHelp =>
      'Verstärkt gedämpfte Farben mehr als bereits kräftige.';

  @override
  String get adjHue => 'Farbton';

  @override
  String get adjHueHelp =>
      'Kleine Farbtonverschiebungen gleichen Blitze, Filter und Wassertyp an.';

  @override
  String get adjHighlightProtection => 'Lichterschutz';

  @override
  String get adjHighlightProtectionHelp =>
      'Verringert die Korrektur in den hellsten Bereichen, um Blitze, Sonne und spiegelnde Ausrüstung zu erhalten.';

  @override
  String get adjHazeReduction => 'Dunst entfernen';

  @override
  String get adjHazeReductionHelp =>
      'Verringert den blaugrünen Schleier und verbessert die Trennung in kontrastarmem Wasser.';

  @override
  String get adjClarity => 'Klarheit';

  @override
  String get adjClarityHelp =>
      'Erhöht den lokalen Kontrast der Mitteltöne, um Struktur sichtbar zu machen. Sanfter als direktes Nachschärfen.';

  @override
  String get adjSharpness => 'Schärfe';

  @override
  String get adjSharpnessHelp =>
      'Verstärkt feine Kanten beim Export. Zu viel betont Rauschen oder Kompressionsartefakte.';

  @override
  String get adjVignette => 'Vignette';

  @override
  String get adjVignetteHelp =>
      'Dunkelt die Bildränder ab, um den Blick zur Mitte zu lenken.';

  @override
  String get compareEdited => 'Bearbeitet';

  @override
  String get compareOriginal => 'Original';

  @override
  String get compareSplit => 'Geteilt';

  @override
  String get previewFitLabel => 'Einpassen';

  @override
  String get previewFillLabel => 'Füllen';

  @override
  String get previewFillAction => 'Vorschaufläche füllen';

  @override
  String get previewFitAction => 'Ganzes Bild einpassen';

  @override
  String get startTagline => 'Privat, direkt auf dem Gerät';

  @override
  String get importHeroTitle => 'Unterwasserfarben zurückholen';

  @override
  String get importHeroTitleQueue => 'Medien hinzufügen oder öffnen';

  @override
  String get importHeroBody =>
      'Wähle ein Foto oder Video zum Bearbeiten. Wähle mehrere für einen Stapel und exportiere dann alles mit einer Bestätigung.';

  @override
  String get importHeroBodyQueue =>
      'Füge weitere Objekte zur Warteschlange hinzu oder bearbeite das ausgewählte Bild weiter.';

  @override
  String get chooseFromPhotos => 'Aus Fotos auswählen';

  @override
  String get importFiles => 'Dateien importieren';

  @override
  String makeMovie(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Film aus $count Objekten erstellen',
      one: 'Film erstellen',
    );
    return '$_temp0';
  }

  @override
  String get editSelected => 'Auswahl bearbeiten';

  @override
  String get showEditedPreview => 'Bearbeitete Vorschau zeigen';

  @override
  String get showSplitPreview => 'Geteilte Vorschau zeigen';

  @override
  String previewFitHint(String action) {
    return '$action. Mit zwei Fingern zoomen, um Details zu prüfen; doppelt tippen setzt den Zoom zurück.';
  }

  @override
  String get reviewExport => 'Export prüfen';

  @override
  String get previousItem => 'Vorheriges Objekt';

  @override
  String get nextItem => 'Nächstes Objekt';

  @override
  String selectionPosition(int current, int total) {
    return 'Auswahl $current/$total';
  }

  @override
  String itemPosition(int current, int total, String name) {
    return '$current von $total – $name';
  }

  @override
  String queueReadyCount(int count) {
    return '$count bereit';
  }

  @override
  String queueProcessingCount(int count) {
    return '$count in Bearbeitung';
  }

  @override
  String queueFailedCount(int count) {
    return '$count fehlgeschlagen';
  }

  @override
  String get copyEditsTooltip => 'Bearbeitungen dieses Fotos kopieren';

  @override
  String copiedEdits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bearbeitungen auf $count Fotos übertragen.',
      one: 'Bearbeitungen auf 1 Foto übertragen.',
    );
    return '$_temp0';
  }

  @override
  String get applyEditsToAllTitle => 'Bearbeitungen auf alle Fotos anwenden?';

  @override
  String get applyEditsToAllBody =>
      'Die Bearbeitungen dieses Fotos werden auf alle anderen Fotos in der Warteschlange angewendet.';

  @override
  String get whiteBalance => 'Weißabgleich';

  @override
  String get manualAdjustments => 'Manuelle Anpassungen';

  @override
  String get videoExportUnavailable => 'Videoexport nicht verfügbar';

  @override
  String get backToEdit => 'Zurück zur Bearbeitung';

  @override
  String get noMediaSelected => 'Keine Medien ausgewählt';

  @override
  String get noMediaSelectedBody =>
      'Wähle ein lokales Foto oder Video, um zu beginnen.';

  @override
  String get goToImport => 'Zum Import';

  @override
  String get importedVideo => 'Importiertes Video';

  @override
  String get importedPhoto => 'Importiertes Foto';

  @override
  String lutNamed(String name) {
    return 'LUT $name';
  }

  @override
  String get retrySelected => 'Erneut versuchen';

  @override
  String get exportingSelected => 'Auswahl wird exportiert …';

  @override
  String get exportedStatus => 'Exportiert';

  @override
  String get exportSelected => 'Auswahl exportieren';

  @override
  String get batchExport => 'Stapelexport';

  @override
  String get selectedItem => 'Ausgewähltes Objekt';

  @override
  String get noItemSelected => 'Kein Objekt ausgewählt';

  @override
  String get videoFrameHelp =>
      'Wähle das Bild für die Editor- und Exportvorschau. Das exportierte Video ändert sich dadurch nicht.';

  @override
  String get previewFrame => 'Vorschaubild';

  @override
  String get framePreviewUnavailable =>
      'Für dieses Video ist auf diesem Gerät keine Bildvorschau verfügbar.';

  @override
  String get preparingVideoTimeline => 'Video wird vorbereitet …';

  @override
  String get trimVideo => 'Video trimmen';

  @override
  String get startSeconds => 'Start (Sekunden)';

  @override
  String get endSeconds => 'Ende (Sekunden)';

  @override
  String rawVideoSummary(int width, int height, String fps, String format) {
    return 'RAW-Video: $width×$height $fps fps $format';
  }

  @override
  String get importCubeLut => '.cube-LUT importieren';

  @override
  String get lutIntensity => 'LUT-Stärke';

  @override
  String get exportSettings => 'Exporteinstellungen';

  @override
  String get exportSettingsSubtitle => 'Format, Qualität und Ziel';

  @override
  String get keepInApp => 'In AquaRecover behalten';

  @override
  String get addToPhotos => 'Zu Fotos hinzufügen';

  @override
  String get exportToFiles => 'In „Dateien“ sichern';

  @override
  String get destinationsHelpWithPhotos =>
      'Wähle ein oder mehrere Ziele. Exporte nach Fotos und Dateien erscheinen nur unter „Lokale Exporte“, wenn eine lokale Kopie aktiviert ist.';

  @override
  String get destinationsHelp =>
      'Wähle ein oder mehrere Ziele. Exporte nach Dateien erscheinen nur unter „Lokale Exporte“, wenn eine lokale Kopie aktiviert ist.';

  @override
  String get jpegQuality => 'JPEG-Qualität';

  @override
  String get stripMetadata => 'Metadaten entfernen';

  @override
  String get keepVideoAudio => 'Videoton behalten';

  @override
  String get beforeAfterImage => 'Vorher/Nachher-Bild';

  @override
  String get beforeAfterImageHelp =>
      'Jedes Foto als ein Bild mit Original und korrigierter Version exportieren';

  @override
  String get beforeAfterSplitHelp =>
      'Geteilt: links das Original, rechts die korrigierte Version';

  @override
  String get beforeAfterSideBySideHelp =>
      'Nebeneinander: Querformate übereinander, Hochformate nebeneinander';

  @override
  String get beforeAfterLabels => 'Vorher/Nachher-Beschriftung';

  @override
  String get beforeAfterLabelsHelp =>
      'Kleine Beschriftungen „Vorher“ und „Nachher“ im Bild zeigen';

  @override
  String get beforeLabel => 'Vorher';

  @override
  String get afterLabel => 'Nachher';

  @override
  String get queue => 'Warteschlange';

  @override
  String itemsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Objekte ausgewählt',
      one: '1 Objekt ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String get noMediaImported => 'Keine Medien importiert.';

  @override
  String editItem(String name) {
    return '$name bearbeiten';
  }

  @override
  String get removeFromQueue => 'Aus Warteschlange entfernen';

  @override
  String removeItemFromQueue(String name) {
    return '$name aus Warteschlange entfernen';
  }

  @override
  String get workingLocally => 'Arbeitet lokal';

  @override
  String get idle => 'Inaktiv';

  @override
  String get exportContinuesInBackground =>
      'Der Export läuft weiter, wenn du die App wechselst. Kehre zu AquaRecover zurück, um den Fortschritt zu sehen.';

  @override
  String get statusReady => 'Bereit.';

  @override
  String get statusNoFileSelected => 'Keine Datei ausgewählt.';

  @override
  String get statusNoPhotosImported =>
      'Es wurden keine lokalen Objekte aus Fotos importiert.';

  @override
  String photosImportFailedStatus(String error) {
    return 'Import aus Fotos fehlgeschlagen: $error';
  }

  @override
  String get photosImportFailed => 'Import aus Fotos fehlgeschlagen';

  @override
  String get itemsSkippedTitle => 'Einige Objekte wurden übersprungen';

  @override
  String itemsSkippedBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count ausgewählte Objekte konnten nicht aus Fotos kopiert werden.',
      one: '1 ausgewähltes Objekt konnte nicht aus Fotos kopiert werden.',
    );
    return '$_temp0 Objekte, die nur in iCloud liegen, musst du zuerst in Fotos laden.';
  }

  @override
  String get waitingForPhotos => 'Warte auf deine Auswahl in Fotos …';

  @override
  String loadedLut(String name) {
    return 'LUT $name geladen.';
  }

  @override
  String get inspectingMedia => 'Importierte Medien werden geprüft …';

  @override
  String inspectingMediaProgress(int done, int total) {
    return 'Importierte Medien werden geprüft … $done/$total';
  }

  @override
  String get noSupportedMedia =>
      'Keine unterstützten, lesbaren Mediendateien gefunden.';

  @override
  String importedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Objekte importiert',
      one: '1 Objekt importiert',
    );
    return '$_temp0';
  }

  @override
  String importedSkipped(int count) {
    return ', $count nicht unterstützte übersprungen';
  }

  @override
  String get importNothingSaved =>
      'Gespeichert wird erst, wenn du den Export bestätigst.';

  @override
  String get preparingExport => 'Export wird vorbereitet …';

  @override
  String failedStatus(String message) {
    return 'Fehlgeschlagen: $message';
  }

  @override
  String get exportFailed => 'Export fehlgeschlagen';

  @override
  String get exportCompleteEmpty =>
      'Export abgeschlossen. Die Warteschlange ist leer.';

  @override
  String exportCompleteRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Export abgeschlossen. $count Objekte verbleiben.',
      one: 'Export abgeschlossen. 1 Objekt verbleibt.',
    );
    return '$_temp0';
  }

  @override
  String get exportingAllMedia =>
      'Alle ausgewählten Medien werden exportiert …';

  @override
  String get queueCancelled => 'Warteschlange abgebrochen.';

  @override
  String batchFinished(int count) {
    return 'Stapelexport beendet: $count exportiert und entfernt';
  }

  @override
  String batchFinishedFailed(int count) {
    return ', $count fehlgeschlagen';
  }

  @override
  String exportingItem(String name) {
    return '$name wird auf diesem Gerät exportiert …';
  }

  @override
  String get chooseFilesFolderFirst =>
      'Wähle vor dem Export einen Ordner in Dateien.';

  @override
  String exportedTo(String file, String destinations) {
    return '$file exportiert nach: $destinations.';
  }

  @override
  String get trimStartNotNumber =>
      'Der Trimmstart muss eine Zahl in Sekunden sein.';

  @override
  String get trimEndNotNumber =>
      'Das Trimmende muss eine Zahl in Sekunden sein.';

  @override
  String get trimStartNegative => 'Der Trimmstart muss null oder größer sein.';

  @override
  String get trimStartTooLate => 'Der Trimmstart muss unter 24 Stunden liegen.';

  @override
  String get trimEndBeforeStart =>
      'Das Trimmende muss nach dem Trimmstart liegen.';

  @override
  String get trimEndTooLate => 'Das Trimmende muss unter 24 Stunden liegen.';

  @override
  String removedFromQueue(String name) {
    return '$name aus der Warteschlange entfernt.';
  }

  @override
  String get cannotCancelExport =>
      'Dieser Export kann nicht sicher abgebrochen werden. Er ist gleich fertig.';

  @override
  String get cancelRequested => 'Abbruch angefordert.';

  @override
  String get chooseExportFolder => 'Exportordner wählen';

  @override
  String get exportFolderUnavailable =>
      'Der ausgewählte Exportordner ist nicht verfügbar.';

  @override
  String get folderUnavailable => 'Ordner nicht verfügbar';

  @override
  String folderUnavailableBody(String error) {
    return 'AquaRecover konnte den ausgewählten Ordner nicht verwenden. $error';
  }

  @override
  String shareExportedTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Alle $count exportierten Dateien teilen',
      one: 'Exportierte Datei teilen',
    );
    return '$_temp0';
  }

  @override
  String shareExportsButton(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Alle $count teilen',
      one: 'Teilen',
    );
    return '$_temp0';
  }

  @override
  String get videoUnavailableBuild =>
      'Videoexport ist in diesem Build nicht verfügbar. Die Fotokorrektur bleibt verfügbar.';

  @override
  String get videoUnavailableIos =>
      'In diesem Build fehlt der native iOS-Videoexport. Baue den iOS-Runner neu oder führe das Bootstrap-Skript aus und versuche es dann erneut.';

  @override
  String get videoUnavailableMacos =>
      'In diesem Build fehlt der native macOS-Videoexport. Baue den macOS-Runner neu oder führe das Bootstrap-Skript aus und versuche es dann erneut.';

  @override
  String get videoRawNeedsFfmpeg =>
      'Der RAW-Videoexport braucht ein ffmpeg-Befehlszeilenprogramm, das eine macOS-App in der Sandbox nicht starten kann. Normale MP4- und MOV-Clips werden nativ exportiert.';

  @override
  String get videoWindowsNeedsFfmpeg =>
      'Der Videoexport unter Windows braucht ffmpeg. Installiere es (zum Beispiel mit „winget install ffmpeg“), starte AquaRecover neu und versuche es erneut. Die Fotokorrektur bleibt verfügbar.';

  @override
  String get photosPermissionDenied =>
      'Der Zugriff auf Fotos wurde nicht erlaubt.';

  @override
  String get timelineEmptyError =>
      'Füge mindestens ein Foto oder einen Clip zum Film hinzu.';

  @override
  String get tapValueToAdjust => 'Tippe auf einen Wert, um ihn anzupassen';

  @override
  String get reset => 'Zurücksetzen';

  @override
  String resetItem(String name) {
    return '$name zurücksetzen';
  }

  @override
  String get openSourceLicenses => 'Open-Source-Lizenzen';

  @override
  String get licensesLoadFailed =>
      'Die Lizenzliste konnte nicht geladen werden.';

  @override
  String licensesIntro(String version) {
    return 'AquaRecover $version enthält die folgende Software. Wähle eine Komponente, um ihren Lizenztext zu lesen.';
  }

  @override
  String get noOtherPhotosInBatch =>
      'In diesem Stapel gibt es keine weiteren Fotos.';

  @override
  String get copyEdits => 'Bearbeitungen kopieren';

  @override
  String get copyEditsSubtitle =>
      'Wähle die Fotos, die diese Werte übernehmen sollen.';

  @override
  String get copyFrom => 'Kopieren von';

  @override
  String selectItem(String name) {
    return '$name auswählen';
  }

  @override
  String deselectItem(String name) {
    return 'Auswahl von $name aufheben';
  }

  @override
  String get applyToAll => 'Auf alle anwenden';

  @override
  String applyToCount(int count) {
    return 'Auf $count anwenden';
  }

  @override
  String get freeformRatio => 'Freies Seitenverhältnis';

  @override
  String get rotateLeft => 'Nach links drehen';

  @override
  String get rotateRight => 'Nach rechts drehen';

  @override
  String get flipHorizontally => 'Horizontal spiegeln';

  @override
  String get flipVertically => 'Vertikal spiegeln';

  @override
  String get resetCrop => 'Zuschnitt zurücksetzen';

  @override
  String get straighten => 'Begradigen';

  @override
  String openToolsNamed(String tool) {
    return 'Werkzeuge „$tool“ öffnen';
  }

  @override
  String collapseToolsNamed(String tool) {
    return 'Werkzeuge „$tool“ einklappen';
  }

  @override
  String openTool(String tool) {
    return '$tool öffnen';
  }

  @override
  String toolsNamed(String tool) {
    return 'Werkzeuge „$tool“';
  }

  @override
  String collapseItem(String name) {
    return '$name einklappen';
  }

  @override
  String get editingTools => 'Bearbeitungswerkzeuge';

  @override
  String get framePreview => 'Bildvorschau';

  @override
  String get representativeFrame => 'Repräsentatives Bild';

  @override
  String get framePreviewUnavailableFormat =>
      'Für dieses Format ist keine Bildvorschau verfügbar';

  @override
  String get previewGeneratedDuringExport =>
      'Die Vorschau entsteht beim Export';

  @override
  String compareModeFrame(String mode) {
    return 'Bild: $mode';
  }

  @override
  String get exportedPhotoPreviewUnavailable =>
      'Vorschau des exportierten Fotos nicht verfügbar.';

  @override
  String get renameHint => 'Umbenennen';

  @override
  String get previewUnavailableFormat =>
      'Für dieses Format ist keine Vorschau verfügbar.';

  @override
  String get cropArea => 'Zuschnittbereich';

  @override
  String get cropAreaHint =>
      'Ziehe an einer Kante oder Ecke, um zuzuschneiden. Ziehe innen, um den Ausschnitt zu verschieben, und zoome mit zwei Fingern, um seine Größe zu ändern.';

  @override
  String get moveCropLeft => 'Ausschnitt nach links';

  @override
  String get moveCropRight => 'Ausschnitt nach rechts';

  @override
  String get moveCropUp => 'Ausschnitt nach oben';

  @override
  String get moveCropDown => 'Ausschnitt nach unten';

  @override
  String get photoUnreadable => 'Dieses Foto konnte nicht gelesen werden.';

  @override
  String get whiteBalanceSubtitle => 'Tippe auf etwas Weißes oder Graues';

  @override
  String whiteBalanceValues(String temperature, String tint) {
    return 'Temperatur $temperature  ·  Tönung $tint';
  }

  @override
  String get whiteBalanceTip =>
      'Sand, eine Schreibtafel oder eine Flasche eignen sich gut. Ziehe, um Stellen zu vergleichen.';

  @override
  String get photosTitle => 'Fotos';

  @override
  String importCount(int count) {
    return '$count importieren';
  }

  @override
  String get openSystemSettings => 'Systemeinstellungen öffnen';

  @override
  String get tryAgain => 'Erneut versuchen';

  @override
  String get noPhotosOrVideos => 'Keine Fotos oder Videos gefunden.';

  @override
  String get noneDownloadedFromPhotos =>
      'Keines der ausgewählten Objekte konnte aus Fotos geladen werden. Öffne sie zuerst in Fotos und versuche es dann erneut.';

  @override
  String itemsNotDownloaded(int count, int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count ausgewählte Objekte konnten nicht aus Fotos geladen werden.',
      one: '1 ausgewähltes Objekt konnte nicht aus Fotos geladen werden.',
    );
    String _temp1 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: 'Die übrigen $remaining werden importiert.',
      one: 'Das übrige wird importiert.',
    );
    return '$_temp0 $_temp1';
  }

  @override
  String get continueAction => 'Fortfahren';

  @override
  String get photosAccessDenied =>
      'Der Zugriff auf Fotos ist deaktiviert. Erlaube AquaRecover in den Systemeinstellungen den Zugriff auf deine Fotomediathek und versuche es dann erneut.';

  @override
  String get photosAccessRestricted =>
      'Der Zugriff auf Fotos ist durch das System oder die Geräteeinstellungen eingeschränkt.';

  @override
  String get photosAccessNotDetermined =>
      'Der Zugriff auf Fotos wurde noch nicht erlaubt. Versuche es erneut, um die Systemabfrage anzuzeigen.';

  @override
  String get photosAccessAvailable => 'Der Zugriff auf Fotos ist verfügbar.';

  @override
  String get photosItemNotLocal =>
      'Das ausgewählte Objekt aus Fotos ist nicht lokal verfügbar. Öffne es in Fotos, um das Original aus iCloud zu laden, und importiere es dann erneut.';

  @override
  String get photosItemUnreadable =>
      'Das ausgewählte Objekt aus Fotos konnte nicht aus dem lokalen Speicher gelesen werden. Wähle ein anderes Objekt oder lade zuerst das Original.';

  @override
  String get photosPickerFailed => 'Die Fotoauswahl ist fehlgeschlagen.';

  @override
  String get presetStrength => 'Stärke der Vorgabe';

  @override
  String get presetStrengthNoneHelp =>
      '„Ohne“ lässt das Bild unverändert. Wähle eine andere Vorgabe, um ihre Stärke anzupassen.';

  @override
  String get presetStrengthHelp =>
      'Skaliert die gewählte Vorgabe und behält spätere manuelle Anpassungen bei.';

  @override
  String presetSummary(String preset, String help) {
    return '$preset: $help';
  }

  @override
  String get waterBlue => 'Blaues Wasser';

  @override
  String get waterGreen => 'Grünes Wasser';

  @override
  String get waterNeutral => 'Kaum Farbstich';

  @override
  String suggestionSemantics(String water, String preset, int strength) {
    return '$water. Vorschlag: $preset mit $strength Prozent.';
  }

  @override
  String suggestionTitle(String water, String preset, int strength) {
    return '$water: $preset $strength %';
  }

  @override
  String get applied => 'Angewendet';

  @override
  String presetChipSemantics(String preset) {
    return 'Vorgabe $preset';
  }

  @override
  String presetChipSuggestedSemantics(String preset) {
    return 'Vorgabe $preset, vorgeschlagen';
  }

  @override
  String get reasonArtificialLight =>
      'Die Farben sind fast neutral und die Lichter fressen aus – typisch für Aufnahmen mit Blitz oder Videolicht.';

  @override
  String get reasonRedFilter =>
      'Rot ist größtenteils vorhanden, aber etwas schwach – wie mit einem roten Tauchfilter.';

  @override
  String get reasonNatural =>
      'Es fehlt nur wenig Rot, daher eine sanfte Korrektur.';

  @override
  String reasonGreenWater(String ratio) {
    return 'Grün überwiegt Blau (Blau/Grün $ratio) – typisch für planktonreiches Wasser oder Seen.';
  }

  @override
  String get reasonDeep =>
      'Es ist kaum noch Rot übrig und die Szene ist dunkel – das spricht für große Tiefe.';

  @override
  String get reasonShallow =>
      'Helle, mäßig blaue Szene – typisch für Flachwasser.';

  @override
  String get reasonAuto =>
      'Typischer Blaustich; die ausgewogene Standardkorrektur passt.';

  @override
  String get queueLocked =>
      'Die Warteschlange ist gesperrt, bis der aktuelle Export fertig ist.';

  @override
  String get noSelectedMedia => 'Keine Medien ausgewählt.';

  @override
  String get selection => 'Auswahl';

  @override
  String itemsInQueue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Objekte in der Warteschlange',
      one: '1 Objekt in der Warteschlange',
    );
    return '$_temp0';
  }

  @override
  String itemWithStatus(String name, String status) {
    return '$name, $status';
  }

  @override
  String get rawVideoSettings => 'RAW-Videoeinstellungen';

  @override
  String get width => 'Breite';

  @override
  String get height => 'Höhe';

  @override
  String get frameRate => 'Bildrate';

  @override
  String get rawVideoNumbersRequired =>
      'Gib ganze Zahlen für Breite und Höhe und eine Zahl für die Bildrate ein.';

  @override
  String get rawVideoTooSmall =>
      'Die Abmessungen des RAW-Videos sind zu klein.';

  @override
  String rawVideoTooLarge(int max) {
    return 'Das RAW-Video darf höchstens $max×$max groß sein.';
  }

  @override
  String rawVideoTooManyPixels(int max) {
    return 'Die Bilder des RAW-Videos sind zu groß. Höchstens $max Pixel pro Bild.';
  }

  @override
  String rawVideoFrameRateRange(String min, String max) {
    return 'Die Bildrate muss zwischen $min und $max fps liegen.';
  }

  @override
  String get renderingPreview => 'Vorschau wird berechnet';

  @override
  String get previewUnavailable => 'Vorschau nicht verfügbar';

  @override
  String get videoFramePreviewUnavailable =>
      'Videobildvorschau nicht verfügbar.';

  @override
  String get videoPreviewUnavailable => 'Videovorschau nicht verfügbar.';

  @override
  String get play => 'Wiedergeben';

  @override
  String get pause => 'Pausieren';

  @override
  String metersValue(String value) {
    return '$value m';
  }

  @override
  String celsiusValue(String value) {
    return '$value °C';
  }

  @override
  String minutesValue(int count) {
    return '$count Min.';
  }

  @override
  String get logbook => 'Logbuch';

  @override
  String get back => 'Zurück';

  @override
  String get importAndExport => 'Importieren und exportieren';

  @override
  String get addDive => 'Tauchgang hinzufügen';

  @override
  String get dives => 'Tauchgänge';

  @override
  String get map => 'Karte';

  @override
  String get noDivesYet => 'Noch keine Tauchgänge';

  @override
  String get noDivesYetBody =>
      'Importiere ein UDDF-Log von deinem Tauchcomputer oder aus Subsurface oder füge einen Tauchgang von Hand hinzu. Dein Logbuch bleibt auf diesem Gerät.';

  @override
  String get importLog => 'Log importieren';

  @override
  String linkedMediaCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count verknüpfte Medien',
      one: '1 verknüpftes Medium',
    );
    return '$_temp0';
  }

  @override
  String get noSitePositions =>
      'Noch kein Tauchplatz hat eine Position. Gib bei einem Tauchgang Breiten- und Längengrad ein, um ihn hier zu sehen.';

  @override
  String get diveSite => 'Tauchplatz';

  @override
  String diveCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tauchgänge',
      one: '1 Tauchgang',
    );
    return '$_temp0';
  }

  @override
  String get importUddfLog => 'UDDF-Log importieren';

  @override
  String get linkPhotosByTime => 'Fotos nach Aufnahmezeit verknüpfen';

  @override
  String get exportGpx => 'GPX exportieren';

  @override
  String get exportUddf => 'UDDF exportieren';

  @override
  String get exportGeoJson => 'GeoJSON exportieren';

  @override
  String get logImported => 'Log importiert';

  @override
  String logImportedBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count neue Tauchgänge wurden hinzugefügt.',
      one: '1 neuer Tauchgang wurde hinzugefügt.',
      zero: 'Alle Tauchgänge aus diesem Log sind schon in deinem Logbuch.',
    );
    return '$_temp0';
  }

  @override
  String get cannotImportFile => 'Datei kann nicht importiert werden';

  @override
  String get noDiveTimes => 'Keine Tauchzeiten';

  @override
  String get noDiveTimesBody =>
      'Tauchgänge brauchen eine Startzeit und eine Dauer, um Fotos zuzuordnen.';

  @override
  String get photosLinked => 'Fotos verknüpft';

  @override
  String photosLinkedBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Fotos und Videos wurden ihren Tauchgängen zugeordnet.',
      one: '1 Foto oder Video wurde seinem Tauchgang zugeordnet.',
      zero:
          'Während deiner Tauchgänge wurden keine neuen Fotos oder Videos aufgenommen.',
    );
    return '$_temp0';
  }

  @override
  String get cannotReadPhotoLibrary =>
      'Fotomediathek kann nicht gelesen werden';

  @override
  String get editDive => 'Tauchgang bearbeiten';

  @override
  String get newDive => 'Neuer Tauchgang';

  @override
  String get save => 'Speichern';

  @override
  String get diveNumber => 'Nummer';

  @override
  String get site => 'Tauchplatz';

  @override
  String get latitude => 'Breitengrad';

  @override
  String get longitude => 'Längengrad';

  @override
  String get maxDepthMeters => 'Max. Tiefe (m)';

  @override
  String get durationMinutes => 'Dauer (Min.)';

  @override
  String get waterTemperatureCelsius => 'Wassertemperatur (°C)';

  @override
  String get buddy => 'Tauchpartner';

  @override
  String get notes => 'Notizen';

  @override
  String get deleteDive => 'Tauchgang löschen';

  @override
  String get dateAndTime => 'Datum und Uhrzeit';

  @override
  String dateAndTimeValue(String date) {
    return 'Datum und Uhrzeit, $date';
  }

  @override
  String get checkPosition => 'Position prüfen';

  @override
  String get checkPositionBody =>
      'Gib Breitengrad (−90 bis 90) und Längengrad (−180 bis 180) in Dezimalgrad ein oder lass beide leer.';

  @override
  String get deleteDiveTitle => 'Diesen Tauchgang löschen?';

  @override
  String get deleteDiveBody =>
      'Fotos und Videos bleiben, wo sie sind; nur der Logbucheintrag wird entfernt.';

  @override
  String get date => 'Datum';

  @override
  String get notSet => 'Nicht festgelegt';

  @override
  String get position => 'Position';

  @override
  String get maxDepth => 'Max. Tiefe';

  @override
  String get duration => 'Dauer';

  @override
  String get waterTemperature => 'Wassertemperatur';

  @override
  String get profile => 'Profil';

  @override
  String depthReadings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tiefenwerte',
      one: '1 Tiefenwert',
    );
    return '$_temp0';
  }

  @override
  String get photosAndVideos => 'Fotos und Videos';

  @override
  String get nothingLinked =>
      'Noch nichts verknüpft. Verknüpfte Medien bleiben, wo sie sind; das Logbuch kopiert sie nie.';

  @override
  String get makeMovieFromDive => 'Film aus diesem Tauchgang erstellen';

  @override
  String get addPhotosAndVideos => 'Fotos und Videos hinzufügen';

  @override
  String get findInPhotos => 'In Fotos suchen';

  @override
  String mediaDepthSuffix(String depth) {
    return ', $depth tief';
  }

  @override
  String get removeFromDive => 'Aus Tauchgang entfernen';

  @override
  String get somethingWentWrong => 'Etwas ist schiefgelaufen';

  @override
  String diveMediaLinkedBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Fotos und Videos wurden verknüpft.',
      one: '1 Foto oder Video wurde verknüpft.',
      zero:
          'Es wurden keine neuen Fotos oder Videos von diesem Tauchgang gefunden.',
    );
    return '$_temp0';
  }

  @override
  String get mediaNotFound => 'Medien nicht gefunden';

  @override
  String get mediaNotFoundBody =>
      'Keines der verknüpften Fotos oder Videos lässt sich öffnen. Vielleicht wurden sie verschoben oder gelöscht.';

  @override
  String diveSiteNamed(String name) {
    return 'Tauchplatz $name';
  }

  @override
  String get osmAttributionSemantics =>
      'Kartendaten © OpenStreetMap-Mitwirkende. Lizenz anzeigen.';

  @override
  String get osmAttribution => '© OpenStreetMap-Mitwirkende';

  @override
  String get diveTitleUnnamed => 'Tauchgang';

  @override
  String diveTitleNumber(int number) {
    return 'Tauchgang $number';
  }

  @override
  String diveTitleNumberSite(int number, String site) {
    return '#$number $site';
  }

  @override
  String coordinatePair(String latitude, String longitude) {
    return '$latitude; $longitude';
  }

  @override
  String get localExportsTitle => 'Lokale Exporte';

  @override
  String get select => 'Auswählen';

  @override
  String get exportsLoadFailed => 'Die Exporte konnten nicht geladen werden.';

  @override
  String get noLocalExports => 'Noch keine lokalen Exporte.';

  @override
  String selectedCount(int count) {
    return '$count ausgewählt';
  }

  @override
  String get deselectAll => 'Auswahl aufheben';

  @override
  String get selectAll => 'Alle auswählen';

  @override
  String localExportCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lokale Exporte',
      one: '1 lokaler Export',
    );
    return '$_temp0';
  }

  @override
  String get deleteAll => 'Alle löschen';

  @override
  String deleteCount(int count) {
    return '$count löschen';
  }

  @override
  String shareSelectedExports(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ausgewählte Exporte teilen',
      one: 'Ausgewählten Export teilen',
    );
    return '$_temp0';
  }

  @override
  String shareCount(int count) {
    return '$count teilen';
  }

  @override
  String get deleteAllExportsTitle => 'Alle lokalen Exporte löschen?';

  @override
  String deleteExportsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Exporte löschen?',
      one: '1 Export löschen?',
    );
    return '$_temp0';
  }

  @override
  String get deleteExportsBody =>
      'Die lokalen Dateien und ihre Einstellungsdateien werden gelöscht. Importierte Originale und Kopien in Fotos bleiben erhalten.';

  @override
  String get someExportsNotDeleted =>
      'Einige Exporte konnten nicht gelöscht werden';

  @override
  String someExportsNotDeletedBody(int failures, int count) {
    return '$failures von $count Dateien wurden vielleicht verschoben oder sind gerade nicht verfügbar.';
  }

  @override
  String get shareExport => 'Export teilen';

  @override
  String get deleteExport => 'Export löschen';

  @override
  String get previewUnavailableShort => 'Vorschau nicht verfügbar.';

  @override
  String get deleteExportTitle => 'Lokalen Export löschen?';

  @override
  String get deleteExportBody =>
      'Die lokale Datei und ihre Einstellungsdatei werden gelöscht. Das importierte Original und Kopien in Fotos bleiben erhalten.';

  @override
  String get exportNotDeleted => 'Export konnte nicht gelöscht werden';

  @override
  String get exportNotDeletedBody =>
      'Die Datei wurde vielleicht verschoben oder ist gerade nicht verfügbar.';

  @override
  String get couldNotShare => 'Teilen nicht möglich';

  @override
  String get shareSheetUnavailable =>
      'Das Teilen-Menü konnte auf diesem Gerät nicht geöffnet werden. Der Export ist weiterhin unter „Lokale Exporte“.';

  @override
  String get exportedFileGone =>
      'Die exportierte Datei ist nicht mehr verfügbar. Vielleicht wurde sie aus „Lokale Exporte“ gelöscht.';

  @override
  String get exportedFilesGone =>
      'Die exportierten Dateien sind nicht mehr verfügbar. Vielleicht wurden sie aus „Lokale Exporte“ gelöscht.';

  @override
  String get previewSize => 'Vorschaugröße';

  @override
  String get dragToResizePreview => 'Ziehen, um die Vorschaugröße zu ändern';

  @override
  String get resetPreviewSize => 'Vorschaugröße zurücksetzen';

  @override
  String get appIconLabel => 'App-Symbol von AquaRecover';

  @override
  String get skip => 'Überspringen';

  @override
  String get tourWelcomeTitle => 'Farben zurückholen – Schritt für Schritt';

  @override
  String get tourWelcomeBody =>
      'AquaRecover hält es einfach: Medien wählen, das Ergebnis verfeinern und dann entscheiden, wohin du exportierst.';

  @override
  String get tourImportTitle => 'Ein Foto oder ein ganzer Stapel';

  @override
  String get tourImportBody =>
      'Ein einzelnes Objekt öffnet sich im Editor. Wählst du mehrere, bleiben sie in einer Warteschlange zusammen, die du jederzeit prüfen kannst.';

  @override
  String get tourEditTitle => 'Bearbeiten, prüfen und vergleichen';

  @override
  String get tourEditBody =>
      'Beginne mit einer Vorgabe und verfeinere dann Anpassungen, Zuschnitt und LUT. Tippe auf einen Wert, um ihn anzupassen; „Zurücksetzen“ stellt den Wert der Vorgabe wieder her.';

  @override
  String get tourExportTitle => 'Du entscheidest, wann und wo gespeichert wird';

  @override
  String get tourExportBody =>
      'Importieren und Bearbeiten erstellen nie eine gespeicherte Kopie. Beim Export wählst du ein oder mehrere Ziele für die fertigen Medien.';

  @override
  String get previousPage => 'Vorherige Seite';

  @override
  String get startEditing => 'Bearbeitung starten';

  @override
  String get next => 'Weiter';

  @override
  String tutorialPageOf(int page, int count) {
    return 'Tour-Seite $page von $count';
  }

  @override
  String get onDevicePrivacy =>
      'Deine Medien werden auf diesem Gerät verarbeitet. AquaRecover lädt sie nirgendwohin hoch.';

  @override
  String get onePhoto => 'Ein Foto';

  @override
  String get batch => 'Stapel';

  @override
  String get tourOnePhotoHint => 'Das Foto öffnet sich direkt im Editor.';

  @override
  String get tourBatchHint =>
      'Drei Objekte liegen bereit in einer bearbeitbaren Warteschlange.';

  @override
  String get tourPresetsHint => 'Wähle einen Ausgangslook.';

  @override
  String get tourAdjustHint => 'Verfeinere jeden Wert.';

  @override
  String get tourCropHint => 'Zuschneiden, drehen und spiegeln.';

  @override
  String get tourLutHint => 'Gib mit einer LUT den letzten Schliff.';

  @override
  String get originalSlashEdited => 'Original / Bearbeitet';

  @override
  String get tourCompareHint =>
      'Probiere „Geteilt“ oder halte die Vorschau gedrückt, um das Original zu sehen.';

  @override
  String editorToolNamed(String tool) {
    return 'Werkzeug $tool';
  }

  @override
  String exportDestinationNamed(String destination) {
    return 'Exportziel $destination';
  }

  @override
  String get tourExportCallout =>
      'Nur ein bestätigter Export schreibt die fertige Datei. Fertige Stapelobjekte verlassen danach die Warteschlange.';

  @override
  String get effectCategoryLook => 'Look';

  @override
  String get effectCategoryLens => 'Objektiv';

  @override
  String get effectCategoryUnderwater => 'Unterwasser';

  @override
  String get effectCategoryMotion => 'Bewegung';

  @override
  String get effectMono => 'Mono';

  @override
  String get effectSepia => 'Sepia';

  @override
  String get effectCyanotype => 'Cyanotypie';

  @override
  String get effectDeepBlue => 'Tiefblau';

  @override
  String get effectVivid => 'Lebendig';

  @override
  String get effectFaded => 'Verblasster Film';

  @override
  String get effectSoftFocus => 'Weichzeichner';

  @override
  String get effectClarity => 'Klarheit';

  @override
  String get effectGrain => 'Filmkorn';

  @override
  String get effectVignette => 'Vignette';

  @override
  String get effectCinemaBars => 'Kinobalken';

  @override
  String get effectSunRays => 'Sonnenstrahlen';

  @override
  String get effectCaustics => 'Lichtnetz';

  @override
  String get effectStrobe => 'Blitzlicht';

  @override
  String get effectSwell => 'Dünung';

  @override
  String get effectDrift => 'Langsames Treiben';

  @override
  String get aspectLandscape => 'Querformat 16:9';

  @override
  String get aspectPortrait => 'Hochformat 9:16';

  @override
  String get aspectSquare => 'Quadrat 1:1';

  @override
  String get aspectPortrait45 => 'Hochformat 4:5';

  @override
  String get fadeColorBlack => 'Schwarz';

  @override
  String get fadeColorWhite => 'Weiß';

  @override
  String get fadeColorDeepBlue => 'Tiefblau';

  @override
  String get animationNone => 'Ohne';

  @override
  String get animationFade => 'Einblenden';

  @override
  String get animationSlideUp => 'Hochgleiten';

  @override
  String get animationPop => 'Aufploppen';

  @override
  String get titleStyleClassic => 'Klassisch';

  @override
  String get titleStyleBox => 'Box';

  @override
  String get titleStyleOutline => 'Kontur';

  @override
  String get titleStyleCaption => 'Untertitel';

  @override
  String get titleStyleDiveStamp => 'Tauchstempel';

  @override
  String get audioRoleMusic => 'Musik';

  @override
  String get audioRoleVoiceover => 'Voiceover';

  @override
  String get audioRoleSound => 'Geräusch';

  @override
  String get audioRoleExtracted => 'Extrahierter Ton';

  @override
  String selectionClip(int index) {
    return 'Clip $index';
  }

  @override
  String selectionPhoto(int index) {
    return 'Foto $index';
  }

  @override
  String get selectionTitle => 'Titel';

  @override
  String get videoOverlay => 'Video-Overlay';

  @override
  String get photoOverlay => 'Foto-Overlay';

  @override
  String get soundFallback => 'Ton';

  @override
  String get defaultTitleText => 'Titel';

  @override
  String extractedAudioName(String name) {
    return 'Ton von $name';
  }

  @override
  String get someFilesSkipped => 'Einige Dateien wurden übersprungen';

  @override
  String filesNotOnTimeline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Dateien können nicht in einen Film (RAW-Video oder unbekannter Typ).',
      one: '1 Datei kann nicht in einen Film (RAW-Video oder unbekannter Typ).',
    );
    return '$_temp0';
  }

  @override
  String get cannotAddOverlay => 'Overlay kann nicht hinzugefügt werden';

  @override
  String get cannotAddOverlayBody =>
      'Wähle ein Foto oder einen Clip in einem Format, das AquaRecover lesen kann. RAW-Videos können nicht in einen Film.';

  @override
  String get cannotReplaceClip => 'Clip kann nicht ersetzt werden';

  @override
  String get cannotReplaceClipBody =>
      'Wähle ein Foto oder einen Clip in einem Format, das AquaRecover lesen kann.';

  @override
  String get nothingToExport => 'Nichts zu exportieren';

  @override
  String get nothingToExportBody =>
      'Füge zuerst mindestens ein Foto oder einen Clip hinzu.';

  @override
  String get movieSaved => 'Film in deinen AquaRecover-Exporten gespeichert.';

  @override
  String get renderCancelled => 'Rendern abgebrochen.';

  @override
  String get savedToPhotos => 'In Fotos gesichert.';

  @override
  String get notSavedToPhotos => 'Nicht in Fotos gesichert';

  @override
  String get backendNoteAndroid =>
      'Überblendungen werden als Abblenden auf Schwarz gerendert';

  @override
  String get backendNoteNoFfmpeg => 'benötigt ffmpeg auf diesem Computer';

  @override
  String get movieName => 'Filmname';

  @override
  String get rename => 'Umbenennen';

  @override
  String get cannotSplitHere => 'Teilen hier nicht möglich';

  @override
  String get cannotSplitHereBody =>
      'Bewege die Abspielposition in das Objekt, weg vom ersten und letzten Bild, und teile dann.';

  @override
  String get toolSplit => 'Teilen';

  @override
  String get toolDuplicate => 'Duplizieren';

  @override
  String get toolDelete => 'Löschen';

  @override
  String get toolEffects => 'Effekte';

  @override
  String get toolColorGrade => 'Farbe';

  @override
  String get toolFade => 'Blende';

  @override
  String get toolSpeed => 'Tempo';

  @override
  String get toolVolume => 'Lautstärke';

  @override
  String get toolDuration => 'Dauer';

  @override
  String get toolOpacity => 'Deckkraft';

  @override
  String get toolAnimate => 'Animation';

  @override
  String get toolLayer => 'Ebene';

  @override
  String get toolEdit => 'Bearbeiten';

  @override
  String get toolAudio => 'Audio';

  @override
  String get toolText => 'Text';

  @override
  String get toolOverlay => 'Overlay';

  @override
  String get toolFormat => 'Format';

  @override
  String get toolMotion => 'Bewegung';

  @override
  String get toolMore => 'Mehr';

  @override
  String get toolTransition => 'Übergang';

  @override
  String get movieTools => 'Filmwerkzeuge';

  @override
  String itemTools(String name) {
    return 'Werkzeuge: $name';
  }

  @override
  String noClipsYet(String aspect) {
    return 'Noch keine Clips · $aspect';
  }

  @override
  String movieSummary(int count, Object aspect, Object duration) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Objekte · $duration · $aspect',
      one: '1 Objekt · $duration · $aspect',
    );
    return '$_temp0';
  }

  @override
  String get exportMovie => 'Film exportieren';

  @override
  String get startWithBestShots => 'Beginne mit deinen besten Aufnahmen';

  @override
  String get startWithBestShotsBody =>
      'Fotos und Clips laufen in der Reihenfolge ab, in der du sie hinzufügst.';

  @override
  String get addPhotosAndClips => 'Fotos und Clips hinzufügen';

  @override
  String playheadOf(String position, String duration) {
    return 'Abspielposition $position von $duration';
  }

  @override
  String get zoomOutTimeline => 'Zeitleiste verkleinern';

  @override
  String get zoomInTimeline => 'Zeitleiste vergrößern';

  @override
  String playPauseShortcut(String action) {
    return '$action (Leertaste)';
  }

  @override
  String secondsValue(String value) {
    return '$value s';
  }

  @override
  String speedValue(String value) {
    return '$value×';
  }

  @override
  String get musicFromFiles => 'Musik aus „Dateien“';

  @override
  String get audioFormatsDetail => 'MP3, M4A, AAC, WAV oder AIFF';

  @override
  String get extractAudioFromClip => 'Ton aus Clip extrahieren';

  @override
  String get putPlayheadOnVideo =>
      'Setze die Abspielposition auf einen Videoclip';

  @override
  String clipGoesSilent(int index) {
    return 'Clip $index wird stumm, sein Ton bekommt eine eigene Spur';
  }

  @override
  String get protectedMusicNote =>
      'Musik aus Apple Music und andere geschützte Titel können nicht verwendet werden.';

  @override
  String effectsOnCount(String name, int count) {
    return '$name · $count aktiv';
  }

  @override
  String get addClipForEffect =>
      'Füge zuerst einen Clip hinzu und gib ihm dann einen Effekt.';

  @override
  String get effectCategoryLooks => 'Looks';

  @override
  String effectIntensity(String name) {
    return 'Intensität: $name';
  }

  @override
  String get remove => 'Entfernen';

  @override
  String get effectTapHint =>
      'Tippe auf einen Effekt, um ihn hinzuzufügen. Tippe erneut, um ihn anzupassen oder zu entfernen.';

  @override
  String get effectHintRemoves => 'Entfernt den Effekt';

  @override
  String get effectHintShowsIntensity => 'Zeigt die Intensität';

  @override
  String get effectHintAdds => 'Fügt den Effekt hinzu';

  @override
  String get selectItemToFade =>
      'Wähle ein Objekt aus, um es ein- oder auszublenden.';

  @override
  String get fadeIn => 'Einblenden';

  @override
  String get fadeOut => 'Ausblenden';

  @override
  String get fadeColorLabel => 'Farbe';

  @override
  String get formatUseLandscape => 'TV, YouTube und Computer';

  @override
  String get formatUsePortrait => 'Storys, Reels und TikTok';

  @override
  String get formatUseSquare => 'Feeds, die quadratisch zuschneiden';

  @override
  String get formatUsePortrait45 => 'Hochformat-Beiträge im Feed';

  @override
  String formatSummary(String aspect, int width, int height) {
    return '$aspect · $width × $height';
  }

  @override
  String get moveEarlier => 'Nach vorne';

  @override
  String get moveLater => 'Nach hinten';

  @override
  String get trimStartToPlayhead => 'Anfang bis Abspielposition kürzen';

  @override
  String get trimEndToPlayhead => 'Ende ab Abspielposition kürzen';

  @override
  String get cannotSetStart => 'Anfang kann nicht gesetzt werden';

  @override
  String get cannotSetStartBody =>
      'Setze die Abspielposition in den ausgewählten Clip, um seinen Anfang festzulegen.';

  @override
  String get cannotSetEnd => 'Ende kann nicht gesetzt werden';

  @override
  String get cannotSetEndBody =>
      'Setze die Abspielposition in den ausgewählten Clip, um sein Ende festzulegen.';

  @override
  String get replaceEllipsis => 'Ersetzen …';

  @override
  String get replaceDetail => 'Behält Farbkorrektur, Effekte und Blenden';

  @override
  String get extractAudio => 'Ton extrahieren';

  @override
  String get extractAudioDetail => 'Verschiebt den Ton auf eine eigene Spur';

  @override
  String get selectPhotoForZoom =>
      'Wähle ein Foto aus, um ihm einen langsamen Zoom zu geben.';

  @override
  String get motionStill => 'Statisch';

  @override
  String get motionZoomIn => 'Einzoomen';

  @override
  String get motionZoomOut => 'Auszoomen';

  @override
  String get motionDriftHint =>
      'Für eine treibende, schwankende Kamera probiere „Langsames Treiben“ und „Dünung“ unter Effekte › Bewegung.';

  @override
  String get selectOverlayForOpacity =>
      'Wähle ein Overlay aus, um seine Deckkraft zu ändern.';

  @override
  String get animation => 'Animation';

  @override
  String get selectOverlayToAnimate =>
      'Wähle ein Overlay oder einen Titel aus, um es zu animieren.';

  @override
  String get animationIn => 'Ein';

  @override
  String get animationOut => 'Aus';

  @override
  String animationDuration(String seconds) {
    return 'Jede Animation dauert $seconds s.';
  }

  @override
  String layerOf(int layer, int count) {
    return '$layer von $count';
  }

  @override
  String get selectOverlayOrTitle => 'Wähle ein Overlay oder einen Titel aus.';

  @override
  String get bringForward => 'Nach vorne bringen';

  @override
  String get bringForwardDetail => 'Erscheint vor der Ebene darüber';

  @override
  String get sendBackward => 'Nach hinten stellen';

  @override
  String get sendBackwardDetail => 'Erscheint hinter der Ebene darunter';

  @override
  String get selectVideoForSpeed =>
      'Wähle einen Videoclip aus, um sein Tempo zu ändern.';

  @override
  String get speedPitchNote =>
      'Der Ton behält seine Tonhöhe. Die Länge in der Zeitleiste ändert sich mit dem Tempo.';

  @override
  String get selectPhotoForDuration =>
      'Wähle ein Foto oder einen Titel aus, um die Länge zu ändern.';

  @override
  String get lengthOnScreen => 'Anzeigedauer';

  @override
  String get halfSecondShorter => 'Eine halbe Sekunde kürzer';

  @override
  String get halfSecondLonger => 'Eine halbe Sekunde länger';

  @override
  String get colorWhite => 'Weiß';

  @override
  String get colorSand => 'Sand';

  @override
  String get colorCoral => 'Koralle';

  @override
  String get colorYellow => 'Gelb';

  @override
  String get colorAqua => 'Aqua';

  @override
  String get colorBlack => 'Schwarz';

  @override
  String get titleStyleBoldBox => 'Fetter Kasten';

  @override
  String get selectTitleToEdit =>
      'Wähle einen Titel aus, um ihn zu bearbeiten.';

  @override
  String get alignLeft => 'Links';

  @override
  String get alignCenter => 'Mitte';

  @override
  String get alignRight => 'Rechts';

  @override
  String get titleSize => 'Größe';

  @override
  String percentOfHeight(int percent) {
    return '$percent % der Höhe';
  }

  @override
  String swatchText(String color) {
    return 'Text in $color';
  }

  @override
  String get transitionCut => 'Schnitt';

  @override
  String get transitionCrossfade => 'Überblenden';

  @override
  String get transitionDipBlack => 'Über Schwarz';

  @override
  String get transitionDipWhite => 'Über Weiß';

  @override
  String clipsRange(int first, int second) {
    return 'Clips $first–$second';
  }

  @override
  String get tapBetweenClips => 'Tippe auf die Taste zwischen zwei Clips.';

  @override
  String get transitionLength => 'Länge aller Übergänge';

  @override
  String applyTransitionToAll(String transition) {
    return '„$transition“ auf alle anwenden';
  }

  @override
  String get noSoundNote => 'Fotos und Titel haben keinen Ton.';

  @override
  String get volumeLevel => 'Pegel';

  @override
  String get muted => 'Stumm';

  @override
  String get mute => 'Stumm';

  @override
  String get gradeStrength => 'Stärke';

  @override
  String get gradeRecovery => 'Korrektur';

  @override
  String get gradeRed => 'Rot';

  @override
  String get gradeBalance => 'Abgleich';

  @override
  String get gradeTemp => 'Temp.';

  @override
  String get gradeHaze => 'Dunst';

  @override
  String get gradeApplyToAll => 'Auf alle anwenden';

  @override
  String get selectToGrade =>
      'Wähle einen Clip oder ein Overlay aus, um die Farbe anzupassen.';

  @override
  String get saveToPhotos => 'In Fotos sichern';

  @override
  String get shareTheMovie => 'Film teilen';

  @override
  String get openExports => 'Exporte öffnen';

  @override
  String movieExportSummary(int width, int height, String duration) {
    return '$width × $height · $duration · H.264 MP4';
  }

  @override
  String cancelWithProgress(int percent) {
    return 'Abbrechen · $percent %';
  }

  @override
  String get exportFrame => 'Format';

  @override
  String get exportQuality => 'Qualität';

  @override
  String get exportFades => 'Blenden';

  @override
  String get allTools => 'Alle Werkzeuge';

  @override
  String get addText => 'Text hinzufügen';

  @override
  String get addOverlayHint => 'Foto- oder Video-Overlay hinzufügen';

  @override
  String get addMusicOrSound => 'Musik oder Ton hinzufügen';

  @override
  String get timelineLabel => 'Zeitleiste';

  @override
  String get zoomIn => 'Vergrößern';

  @override
  String get zoomOut => 'Verkleinern';

  @override
  String get trimStart => 'Anfang kürzen';

  @override
  String get trimEnd => 'Ende kürzen';

  @override
  String get dragSideways => 'Seitwärts ziehen';

  @override
  String overlayLayerN(int index) {
    return 'Overlay-Ebene $index';
  }

  @override
  String audioLaneN(int index) {
    return 'Tonspur $index';
  }

  @override
  String get unmuteClipAudio => 'Clipton einschalten';

  @override
  String get muteClipAudio => 'Clipton stummschalten';

  @override
  String get mainTrack => 'Hauptspur';

  @override
  String get overlayFallback => 'Overlay';

  @override
  String timelineItemDescription(
    String kind,
    String name,
    String start,
    String seconds,
  ) {
    return '$kind $name, beginnt bei $start, $seconds Sekunden';
  }

  @override
  String transitionNamed(String name) {
    return 'Übergang: $name';
  }

  @override
  String get addTransition => 'Übergang hinzufügen';

  @override
  String transitionBeforeClip(int index) {
    return 'Übergang vor Clip $index';
  }

  @override
  String clipSpeedSemantics(String speed) {
    return '$speed-fache Geschwindigkeit';
  }

  @override
  String clipEffectsSemantics(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Effekte',
      one: '1 Effekt',
    );
    return '$_temp0';
  }

  @override
  String get touchAndHoldToMove => 'Halten zum Verschieben';

  @override
  String defaultMovieName(String date) {
    return 'Tauchgang, $date';
  }

  @override
  String deleteNamedQuestion(String name) {
    return '„$name“ löschen?';
  }

  @override
  String get deleteMovieBody =>
      'Nur das Filmprojekt wird entfernt. Deine Fotos, Clips und exportierten Filme bleiben erhalten.';

  @override
  String get madeOnThisDevice => 'Auf diesem Gerät erstellt';

  @override
  String movieCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Filme',
      one: '1 Film',
    );
    return '$_temp0';
  }

  @override
  String get newMovie => 'Neuer Film';

  @override
  String get turnDiveIntoMovie => 'Mach aus einem Tauchgang einen Film';

  @override
  String get turnDiveIntoMovieBody =>
      'Reihe Fotos und Clips aneinander, gib jedem die passende Farbe und exportiere einen Film, ohne dieses Gerät zu verlassen.';

  @override
  String get recent => 'Zuletzt';

  @override
  String get swipeToDeleteMovie =>
      'Streiche nach links oder halte einen Film gedrückt, um ihn zu löschen.';

  @override
  String get open => 'Öffnen';

  @override
  String titleQuoted(String text) {
    return 'Titel „$text“';
  }

  @override
  String selectedOnCanvas(String name) {
    return '$name auf der Leinwand ausgewählt';
  }

  @override
  String get movieCanvas => 'Filmleinwand';

  @override
  String get canvasSelectedHint =>
      'Ziehen zum Verschieben, Auf- und Zuziehen zum Skalieren, mit zwei Fingern drehen';

  @override
  String get canvasHint =>
      'Tippe, um den sichtbaren Clip oder das Overlay auszuwählen';

  @override
  String get moveLeft => 'Nach links';

  @override
  String get moveRight => 'Nach rechts';

  @override
  String get moveUp => 'Nach oben';

  @override
  String get moveDown => 'Nach unten';

  @override
  String get makeLarger => 'Vergrößern';

  @override
  String get makeSmaller => 'Verkleinern';

  @override
  String get rotateClockwise => 'Im Uhrzeigersinn drehen';
}
