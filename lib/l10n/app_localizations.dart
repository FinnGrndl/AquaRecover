import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('de'),
  ];

  /// App name. Not translated.
  ///
  /// In en, this message translates to:
  /// **'AquaRecover'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @manage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manage;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @original.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get original;

  /// No description provided for @selected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get selected;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// Back button from the editor to the start screen.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryBack;

  /// Button that starts an export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportAction;

  /// Title of the export screen.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportTitle;

  /// No description provided for @exportAll.
  ///
  /// In en, this message translates to:
  /// **'Export all'**
  String get exportAll;

  /// No description provided for @exportingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Exporting...'**
  String get exportingEllipsis;

  /// Short progress label in a narrow button.
  ///
  /// In en, this message translates to:
  /// **'Exporting'**
  String get exportingShort;

  /// No description provided for @licenses.
  ///
  /// In en, this message translates to:
  /// **'Licenses'**
  String get licenses;

  /// No description provided for @movies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get movies;

  /// No description provided for @diveLogbook.
  ///
  /// In en, this message translates to:
  /// **'Dive logbook'**
  String get diveLogbook;

  /// No description provided for @localExports.
  ///
  /// In en, this message translates to:
  /// **'Local exports'**
  String get localExports;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About AquaRecover'**
  String get aboutApp;

  /// No description provided for @quickTour.
  ///
  /// In en, this message translates to:
  /// **'Quick Tour'**
  String get quickTour;

  /// No description provided for @aboutBody.
  ///
  /// In en, this message translates to:
  /// **'Version {version}\\n\\nOn-device underwater color recovery for photos, RAW stills, videos, LUTs, and local exports.'**
  String aboutBody(String version);

  /// The Photos app as an export destination.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get destinationPhotos;

  /// The Files app or file system as an export destination.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get destinationFiles;

  /// No description provided for @presetNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get presetNone;

  /// No description provided for @presetAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get presetAuto;

  /// No description provided for @presetNatural.
  ///
  /// In en, this message translates to:
  /// **'Natural'**
  String get presetNatural;

  /// No description provided for @presetVivid.
  ///
  /// In en, this message translates to:
  /// **'Vivid reef'**
  String get presetVivid;

  /// No description provided for @presetDeep.
  ///
  /// In en, this message translates to:
  /// **'Deep dive'**
  String get presetDeep;

  /// No description provided for @presetMacro.
  ///
  /// In en, this message translates to:
  /// **'Macro'**
  String get presetMacro;

  /// No description provided for @presetShallow.
  ///
  /// In en, this message translates to:
  /// **'Shallow'**
  String get presetShallow;

  /// No description provided for @presetGreenWater.
  ///
  /// In en, this message translates to:
  /// **'Green water'**
  String get presetGreenWater;

  /// No description provided for @presetRedFilter.
  ///
  /// In en, this message translates to:
  /// **'Red filter'**
  String get presetRedFilter;

  /// No description provided for @presetArtificialLight.
  ///
  /// In en, this message translates to:
  /// **'Artificial light'**
  String get presetArtificialLight;

  /// No description provided for @presetNoneHelp.
  ///
  /// In en, this message translates to:
  /// **'Leaves the image unchanged.'**
  String get presetNoneHelp;

  /// No description provided for @presetAutoHelp.
  ///
  /// In en, this message translates to:
  /// **'Balanced one-tap correction for common blue-green water.'**
  String get presetAutoHelp;

  /// No description provided for @presetNaturalHelp.
  ///
  /// In en, this message translates to:
  /// **'Lower contrast and saturation for a documentary look.'**
  String get presetNaturalHelp;

  /// No description provided for @presetVividHelp.
  ///
  /// In en, this message translates to:
  /// **'Extra contrast and color for reef scenes.'**
  String get presetVividHelp;

  /// No description provided for @presetDeepHelp.
  ///
  /// In en, this message translates to:
  /// **'Stronger red recovery for deeper dives.'**
  String get presetDeepHelp;

  /// No description provided for @presetMacroHelp.
  ///
  /// In en, this message translates to:
  /// **'More local detail for close subjects.'**
  String get presetMacroHelp;

  /// No description provided for @presetShallowHelp.
  ///
  /// In en, this message translates to:
  /// **'Gentle correction for snorkeling and sunlit shallow water.'**
  String get presetShallowHelp;

  /// No description provided for @presetGreenWaterHelp.
  ///
  /// In en, this message translates to:
  /// **'Counters green plankton-rich water without overdoing magenta.'**
  String get presetGreenWaterHelp;

  /// No description provided for @presetRedFilterHelp.
  ///
  /// In en, this message translates to:
  /// **'Compensates footage shot with a red dive filter.'**
  String get presetRedFilterHelp;

  /// No description provided for @presetArtificialLightHelp.
  ///
  /// In en, this message translates to:
  /// **'Protects highlights from torches and strobes.'**
  String get presetArtificialLightHelp;

  /// No description provided for @mediaKindPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get mediaKindPhoto;

  /// No description provided for @mediaKindRawPhoto.
  ///
  /// In en, this message translates to:
  /// **'RAW photo'**
  String get mediaKindRawPhoto;

  /// No description provided for @mediaKindVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get mediaKindVideo;

  /// No description provided for @mediaKindRawVideo.
  ///
  /// In en, this message translates to:
  /// **'RAW video'**
  String get mediaKindRawVideo;

  /// No description provided for @jobStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get jobStatusReady;

  /// No description provided for @jobStatusProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get jobStatusProcessing;

  /// No description provided for @jobStatusComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get jobStatusComplete;

  /// No description provided for @jobStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get jobStatusFailed;

  /// No description provided for @beforeAfterSideBySide.
  ///
  /// In en, this message translates to:
  /// **'Side by side'**
  String get beforeAfterSideBySide;

  /// No description provided for @beforeAfterSplit.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get beforeAfterSplit;

  /// No description provided for @exportPresetSocial.
  ///
  /// In en, this message translates to:
  /// **'Social'**
  String get exportPresetSocial;

  /// No description provided for @exportPresetArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get exportPresetArchive;

  /// No description provided for @exportPresetProEdit.
  ///
  /// In en, this message translates to:
  /// **'Pro edit'**
  String get exportPresetProEdit;

  /// No description provided for @lutNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get lutNone;

  /// No description provided for @lutCoralWarm.
  ///
  /// In en, this message translates to:
  /// **'Coral Warm'**
  String get lutCoralWarm;

  /// No description provided for @lutBlueWater.
  ///
  /// In en, this message translates to:
  /// **'Blue Water'**
  String get lutBlueWater;

  /// No description provided for @lutGreenWater.
  ///
  /// In en, this message translates to:
  /// **'Green Water'**
  String get lutGreenWater;

  /// No description provided for @lutCustomCube.
  ///
  /// In en, this message translates to:
  /// **'Custom .cube'**
  String get lutCustomCube;

  /// No description provided for @cropOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get cropOriginal;

  /// No description provided for @cropFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get cropFree;

  /// No description provided for @cropSquare.
  ///
  /// In en, this message translates to:
  /// **'Square'**
  String get cropSquare;

  /// No description provided for @workflowImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get workflowImport;

  /// No description provided for @workflowEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get workflowEdit;

  /// No description provided for @workflowExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get workflowExport;

  /// No description provided for @toolPresets.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get toolPresets;

  /// No description provided for @toolAdjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust'**
  String get toolAdjust;

  /// No description provided for @toolCrop.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get toolCrop;

  /// No description provided for @toolColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get toolColor;

  /// No description provided for @toolDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get toolDetails;

  /// No description provided for @toolLut.
  ///
  /// In en, this message translates to:
  /// **'LUT'**
  String get toolLut;

  /// No description provided for @toolVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get toolVideo;

  /// No description provided for @toolPresetsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Starting profile and strength'**
  String get toolPresetsSubtitle;

  /// No description provided for @toolAdjustSubtitle.
  ///
  /// In en, this message translates to:
  /// **'All image adjustments'**
  String get toolAdjustSubtitle;

  /// No description provided for @toolCropSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Crop, rotate, and flip'**
  String get toolCropSubtitle;

  /// No description provided for @toolColorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Water cast and color balance'**
  String get toolColorSubtitle;

  /// No description provided for @toolDetailsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Haze, clarity, and sharpening'**
  String get toolDetailsSubtitle;

  /// No description provided for @toolLutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Look-up table and vignette'**
  String get toolLutSubtitle;

  /// No description provided for @toolVideoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Preview frame and trim'**
  String get toolVideoSubtitle;

  /// No description provided for @adjRecovery.
  ///
  /// In en, this message translates to:
  /// **'Water correction'**
  String get adjRecovery;

  /// No description provided for @adjRecoveryHelp.
  ///
  /// In en, this message translates to:
  /// **'Controls the underwater cast-recovery stage only. It strengthens color recovery and local neutralization, but does not scale exposure, contrast, saturation, or sharpening.'**
  String get adjRecoveryHelp;

  /// No description provided for @adjContrastStretch.
  ///
  /// In en, this message translates to:
  /// **'Contrast stretch'**
  String get adjContrastStretch;

  /// No description provided for @adjContrastStretchHelp.
  ///
  /// In en, this message translates to:
  /// **'Expands the measured dark-to-bright range. High values can make murky scenes punchier but may clip detail.'**
  String get adjContrastStretchHelp;

  /// No description provided for @adjContrast.
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get adjContrast;

  /// No description provided for @adjContrastHelp.
  ///
  /// In en, this message translates to:
  /// **'Changes separation around the midtones without re-running the underwater color recovery.'**
  String get adjContrastHelp;

  /// No description provided for @adjGamma.
  ///
  /// In en, this message translates to:
  /// **'Gamma'**
  String get adjGamma;

  /// No description provided for @adjGammaHelp.
  ///
  /// In en, this message translates to:
  /// **'Moves midtone brightness while keeping the black and white endpoints mostly fixed.'**
  String get adjGammaHelp;

  /// No description provided for @adjBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get adjBrightness;

  /// No description provided for @adjBrightnessHelp.
  ///
  /// In en, this message translates to:
  /// **'Adds or removes a uniform amount of light after the main correction.'**
  String get adjBrightnessHelp;

  /// No description provided for @adjExposure.
  ///
  /// In en, this message translates to:
  /// **'Exposure'**
  String get adjExposure;

  /// No description provided for @adjExposureHelp.
  ///
  /// In en, this message translates to:
  /// **'Multiplies scene brightness like a small exposure adjustment. It affects shadows and highlights together.'**
  String get adjExposureHelp;

  /// No description provided for @adjHighlights.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get adjHighlights;

  /// No description provided for @adjHighlightsHelp.
  ///
  /// In en, this message translates to:
  /// **'Brightens or darkens the lightest parts while protecting the rest of the tonal range.'**
  String get adjHighlightsHelp;

  /// No description provided for @adjShadows.
  ///
  /// In en, this message translates to:
  /// **'Shadows'**
  String get adjShadows;

  /// No description provided for @adjShadowsHelp.
  ///
  /// In en, this message translates to:
  /// **'Opens or deepens darker areas without applying a full-image brightness change.'**
  String get adjShadowsHelp;

  /// No description provided for @adjBlackPoint.
  ///
  /// In en, this message translates to:
  /// **'Black point'**
  String get adjBlackPoint;

  /// No description provided for @adjBlackPointHelp.
  ///
  /// In en, this message translates to:
  /// **'Deepens the darkest tones. Increase carefully to avoid losing shadow detail.'**
  String get adjBlackPointHelp;

  /// No description provided for @adjTemperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get adjTemperature;

  /// No description provided for @adjTemperatureHelp.
  ///
  /// In en, this message translates to:
  /// **'Final warm-cool trim after the water correction. The white balance picker sets it from a tap.'**
  String get adjTemperatureHelp;

  /// No description provided for @adjTint.
  ///
  /// In en, this message translates to:
  /// **'Tint'**
  String get adjTint;

  /// No description provided for @adjTintHelp.
  ///
  /// In en, this message translates to:
  /// **'Final green-magenta trim. Positive values remove a leftover green cast.'**
  String get adjTintHelp;

  /// No description provided for @adjRedRecovery.
  ///
  /// In en, this message translates to:
  /// **'Red recovery'**
  String get adjRedRecovery;

  /// No description provided for @adjRedRecoveryHelp.
  ///
  /// In en, this message translates to:
  /// **'Targets warm colors absorbed by water. Its result is multiplied by Water correction, so both controls work together.'**
  String get adjRedRecoveryHelp;

  /// No description provided for @adjAutoWhiteBalance.
  ///
  /// In en, this message translates to:
  /// **'Auto white balance'**
  String get adjAutoWhiteBalance;

  /// No description provided for @adjAutoWhiteBalanceHelp.
  ///
  /// In en, this message translates to:
  /// **'Balances the average red, green, and blue levels within safe bounds. Lower it when intentional lighting should stay warm or cool.'**
  String get adjAutoWhiteBalanceHelp;

  /// No description provided for @adjSaturation.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get adjSaturation;

  /// No description provided for @adjSaturationHelp.
  ///
  /// In en, this message translates to:
  /// **'Changes the intensity of all colors equally. High values can exaggerate color noise and water tint.'**
  String get adjSaturationHelp;

  /// No description provided for @adjVibrance.
  ///
  /// In en, this message translates to:
  /// **'Vibrance'**
  String get adjVibrance;

  /// No description provided for @adjVibranceHelp.
  ///
  /// In en, this message translates to:
  /// **'Boosts muted colors more than colors that are already strong.'**
  String get adjVibranceHelp;

  /// No description provided for @adjHue.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get adjHue;

  /// No description provided for @adjHueHelp.
  ///
  /// In en, this message translates to:
  /// **'Small hue rotations help match strobes, filters, and water type.'**
  String get adjHueHelp;

  /// No description provided for @adjHighlightProtection.
  ///
  /// In en, this message translates to:
  /// **'Highlight protection'**
  String get adjHighlightProtection;

  /// No description provided for @adjHighlightProtectionHelp.
  ///
  /// In en, this message translates to:
  /// **'Reduces correction in the brightest areas to preserve strobes, the sun, and reflective equipment.'**
  String get adjHighlightProtectionHelp;

  /// No description provided for @adjHazeReduction.
  ///
  /// In en, this message translates to:
  /// **'Haze reduction'**
  String get adjHazeReduction;

  /// No description provided for @adjHazeReductionHelp.
  ///
  /// In en, this message translates to:
  /// **'Reduces blue-green veil and increases separation in low-contrast water.'**
  String get adjHazeReductionHelp;

  /// No description provided for @adjClarity.
  ///
  /// In en, this message translates to:
  /// **'Clarity'**
  String get adjClarity;

  /// No description provided for @adjClarityHelp.
  ///
  /// In en, this message translates to:
  /// **'Adds local midtone contrast to reveal texture. It is gentler than sharpening edges directly.'**
  String get adjClarityHelp;

  /// No description provided for @adjSharpness.
  ///
  /// In en, this message translates to:
  /// **'Sharpness'**
  String get adjSharpness;

  /// No description provided for @adjSharpnessHelp.
  ///
  /// In en, this message translates to:
  /// **'Strengthens fine edges during export. Too much can emphasize noise or compression artifacts.'**
  String get adjSharpnessHelp;

  /// No description provided for @adjVignette.
  ///
  /// In en, this message translates to:
  /// **'Vignette'**
  String get adjVignette;

  /// No description provided for @adjVignetteHelp.
  ///
  /// In en, this message translates to:
  /// **'Darkens the image edges to guide attention toward the center.'**
  String get adjVignetteHelp;

  /// No description provided for @compareEdited.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get compareEdited;

  /// No description provided for @compareOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get compareOriginal;

  /// No description provided for @compareSplit.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get compareSplit;

  /// No description provided for @previewFitLabel.
  ///
  /// In en, this message translates to:
  /// **'Fit'**
  String get previewFitLabel;

  /// No description provided for @previewFillLabel.
  ///
  /// In en, this message translates to:
  /// **'Fill'**
  String get previewFillLabel;

  /// No description provided for @previewFillAction.
  ///
  /// In en, this message translates to:
  /// **'Fill preview area'**
  String get previewFillAction;

  /// No description provided for @previewFitAction.
  ///
  /// In en, this message translates to:
  /// **'Fit entire image'**
  String get previewFitAction;

  /// No description provided for @startTagline.
  ///
  /// In en, this message translates to:
  /// **'Private, on-device restoration'**
  String get startTagline;

  /// No description provided for @importHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore underwater color'**
  String get importHeroTitle;

  /// No description provided for @importHeroTitleQueue.
  ///
  /// In en, this message translates to:
  /// **'Add or open media'**
  String get importHeroTitleQueue;

  /// No description provided for @importHeroBody.
  ///
  /// In en, this message translates to:
  /// **'Choose one photo or video to edit. Select several to prepare one batch, then export everything with one confirmation.'**
  String get importHeroBody;

  /// No description provided for @importHeroBodyQueue.
  ///
  /// In en, this message translates to:
  /// **'Add more items to the queue or continue with the selected image.'**
  String get importHeroBodyQueue;

  /// No description provided for @chooseFromPhotos.
  ///
  /// In en, this message translates to:
  /// **'Choose from Photos'**
  String get chooseFromPhotos;

  /// No description provided for @importFiles.
  ///
  /// In en, this message translates to:
  /// **'Import Files'**
  String get importFiles;

  /// No description provided for @makeMovie.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Make a movie} other{Make a movie from {count} items}}'**
  String makeMovie(int count);

  /// No description provided for @editSelected.
  ///
  /// In en, this message translates to:
  /// **'Edit selected'**
  String get editSelected;

  /// No description provided for @showEditedPreview.
  ///
  /// In en, this message translates to:
  /// **'Show edited preview'**
  String get showEditedPreview;

  /// No description provided for @showSplitPreview.
  ///
  /// In en, this message translates to:
  /// **'Show split preview'**
  String get showSplitPreview;

  /// No description provided for @previewFitHint.
  ///
  /// In en, this message translates to:
  /// **'{action}. Pinch with two fingers to inspect details; double-tap to reset zoom.'**
  String previewFitHint(String action);

  /// No description provided for @reviewExport.
  ///
  /// In en, this message translates to:
  /// **'Review export'**
  String get reviewExport;

  /// No description provided for @previousItem.
  ///
  /// In en, this message translates to:
  /// **'Previous item'**
  String get previousItem;

  /// No description provided for @nextItem.
  ///
  /// In en, this message translates to:
  /// **'Next item'**
  String get nextItem;

  /// No description provided for @selectionPosition.
  ///
  /// In en, this message translates to:
  /// **'Selection {current}/{total}'**
  String selectionPosition(int current, int total);

  /// No description provided for @itemPosition.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total} - {name}'**
  String itemPosition(int current, int total, String name);

  /// No description provided for @queueReadyCount.
  ///
  /// In en, this message translates to:
  /// **'{count} ready'**
  String queueReadyCount(int count);

  /// No description provided for @queueProcessingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} processing'**
  String queueProcessingCount(int count);

  /// No description provided for @queueFailedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} failed'**
  String queueFailedCount(int count);

  /// No description provided for @copyEditsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy this photo’s edits'**
  String get copyEditsTooltip;

  /// No description provided for @copiedEdits.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Copied edits to 1 photo.} other{Copied edits to {count} photos.}}'**
  String copiedEdits(int count);

  /// No description provided for @applyEditsToAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Apply edits to all photos?'**
  String get applyEditsToAllTitle;

  /// No description provided for @applyEditsToAllBody.
  ///
  /// In en, this message translates to:
  /// **'This photo’s edits will be applied to all other photos in the queue.'**
  String get applyEditsToAllBody;

  /// No description provided for @whiteBalance.
  ///
  /// In en, this message translates to:
  /// **'White balance'**
  String get whiteBalance;

  /// No description provided for @manualAdjustments.
  ///
  /// In en, this message translates to:
  /// **'Manual adjustments'**
  String get manualAdjustments;

  /// No description provided for @videoExportUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Video export unavailable'**
  String get videoExportUnavailable;

  /// No description provided for @backToEdit.
  ///
  /// In en, this message translates to:
  /// **'Back to edit'**
  String get backToEdit;

  /// No description provided for @noMediaSelected.
  ///
  /// In en, this message translates to:
  /// **'No media selected'**
  String get noMediaSelected;

  /// No description provided for @noMediaSelectedBody.
  ///
  /// In en, this message translates to:
  /// **'Choose a local photo or video to begin.'**
  String get noMediaSelectedBody;

  /// No description provided for @goToImport.
  ///
  /// In en, this message translates to:
  /// **'Go to import'**
  String get goToImport;

  /// No description provided for @importedVideo.
  ///
  /// In en, this message translates to:
  /// **'Imported video'**
  String get importedVideo;

  /// No description provided for @importedPhoto.
  ///
  /// In en, this message translates to:
  /// **'Imported photo'**
  String get importedPhoto;

  /// No description provided for @lutNamed.
  ///
  /// In en, this message translates to:
  /// **'LUT {name}'**
  String lutNamed(String name);

  /// No description provided for @retrySelected.
  ///
  /// In en, this message translates to:
  /// **'Retry selected'**
  String get retrySelected;

  /// No description provided for @exportingSelected.
  ///
  /// In en, this message translates to:
  /// **'Exporting selected...'**
  String get exportingSelected;

  /// No description provided for @exportedStatus.
  ///
  /// In en, this message translates to:
  /// **'Exported'**
  String get exportedStatus;

  /// No description provided for @exportSelected.
  ///
  /// In en, this message translates to:
  /// **'Export selected'**
  String get exportSelected;

  /// No description provided for @batchExport.
  ///
  /// In en, this message translates to:
  /// **'Batch export'**
  String get batchExport;

  /// No description provided for @selectedItem.
  ///
  /// In en, this message translates to:
  /// **'Selected item'**
  String get selectedItem;

  /// No description provided for @noItemSelected.
  ///
  /// In en, this message translates to:
  /// **'No item selected'**
  String get noItemSelected;

  /// No description provided for @videoFrameHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose the frame used in the editor and export preview. This does not change the exported video timeline.'**
  String get videoFrameHelp;

  /// No description provided for @previewFrame.
  ///
  /// In en, this message translates to:
  /// **'Preview frame'**
  String get previewFrame;

  /// No description provided for @framePreviewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Frame preview is not available for this video on this device.'**
  String get framePreviewUnavailable;

  /// No description provided for @preparingVideoTimeline.
  ///
  /// In en, this message translates to:
  /// **'Preparing video timeline…'**
  String get preparingVideoTimeline;

  /// No description provided for @trimVideo.
  ///
  /// In en, this message translates to:
  /// **'Trim video'**
  String get trimVideo;

  /// No description provided for @startSeconds.
  ///
  /// In en, this message translates to:
  /// **'Start seconds'**
  String get startSeconds;

  /// No description provided for @endSeconds.
  ///
  /// In en, this message translates to:
  /// **'End seconds'**
  String get endSeconds;

  /// No description provided for @rawVideoSummary.
  ///
  /// In en, this message translates to:
  /// **'RAW video: {width}x{height} {fps}fps {format}'**
  String rawVideoSummary(int width, int height, String fps, String format);

  /// No description provided for @importCubeLut.
  ///
  /// In en, this message translates to:
  /// **'Import .cube LUT'**
  String get importCubeLut;

  /// No description provided for @lutIntensity.
  ///
  /// In en, this message translates to:
  /// **'LUT intensity'**
  String get lutIntensity;

  /// No description provided for @exportSettings.
  ///
  /// In en, this message translates to:
  /// **'Export settings'**
  String get exportSettings;

  /// No description provided for @exportSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Format, quality, and destination'**
  String get exportSettingsSubtitle;

  /// No description provided for @keepInApp.
  ///
  /// In en, this message translates to:
  /// **'Keep in AquaRecover'**
  String get keepInApp;

  /// No description provided for @addToPhotos.
  ///
  /// In en, this message translates to:
  /// **'Add to Photos'**
  String get addToPhotos;

  /// No description provided for @exportToFiles.
  ///
  /// In en, this message translates to:
  /// **'Export to Files'**
  String get exportToFiles;

  /// No description provided for @destinationsHelpWithPhotos.
  ///
  /// In en, this message translates to:
  /// **'Choose one or more destinations. Photos and Files exports do not appear under Local Exports unless a local copy is enabled.'**
  String get destinationsHelpWithPhotos;

  /// No description provided for @destinationsHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose one or more destinations. Files exports do not appear under Local Exports unless a local copy is enabled.'**
  String get destinationsHelp;

  /// No description provided for @jpegQuality.
  ///
  /// In en, this message translates to:
  /// **'JPEG quality'**
  String get jpegQuality;

  /// No description provided for @stripMetadata.
  ///
  /// In en, this message translates to:
  /// **'Strip metadata'**
  String get stripMetadata;

  /// No description provided for @keepVideoAudio.
  ///
  /// In en, this message translates to:
  /// **'Keep video audio'**
  String get keepVideoAudio;

  /// No description provided for @beforeAfterImage.
  ///
  /// In en, this message translates to:
  /// **'Before/After image'**
  String get beforeAfterImage;

  /// No description provided for @beforeAfterImageHelp.
  ///
  /// In en, this message translates to:
  /// **'Export each photo as one image showing the original and the restored version'**
  String get beforeAfterImageHelp;

  /// No description provided for @beforeAfterSplitHelp.
  ///
  /// In en, this message translates to:
  /// **'Split: original on the left half, restored on the right'**
  String get beforeAfterSplitHelp;

  /// No description provided for @beforeAfterSideBySideHelp.
  ///
  /// In en, this message translates to:
  /// **'Side by side: landscape photos are stacked, portrait photos sit next to each other'**
  String get beforeAfterSideBySideHelp;

  /// No description provided for @beforeAfterLabels.
  ///
  /// In en, this message translates to:
  /// **'Before and After labels'**
  String get beforeAfterLabels;

  /// No description provided for @beforeAfterLabelsHelp.
  ///
  /// In en, this message translates to:
  /// **'Show small Before and After labels on the image'**
  String get beforeAfterLabelsHelp;

  /// Label burned into the exported before/after image.
  ///
  /// In en, this message translates to:
  /// **'Before'**
  String get beforeLabel;

  /// Label burned into the exported before/after image.
  ///
  /// In en, this message translates to:
  /// **'After'**
  String get afterLabel;

  /// No description provided for @queue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queue;

  /// No description provided for @itemsSelected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item selected} other{{count} items selected}}'**
  String itemsSelected(int count);

  /// No description provided for @noMediaImported.
  ///
  /// In en, this message translates to:
  /// **'No media imported.'**
  String get noMediaImported;

  /// No description provided for @editItem.
  ///
  /// In en, this message translates to:
  /// **'Edit {name}'**
  String editItem(String name);

  /// No description provided for @removeFromQueue.
  ///
  /// In en, this message translates to:
  /// **'Remove from queue'**
  String get removeFromQueue;

  /// No description provided for @removeItemFromQueue.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from queue'**
  String removeItemFromQueue(String name);

  /// No description provided for @workingLocally.
  ///
  /// In en, this message translates to:
  /// **'Working locally'**
  String get workingLocally;

  /// No description provided for @idle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get idle;

  /// No description provided for @exportContinuesInBackground.
  ///
  /// In en, this message translates to:
  /// **'The export can continue if you switch apps. Return to AquaRecover to check its progress.'**
  String get exportContinuesInBackground;

  /// No description provided for @statusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready.'**
  String get statusReady;

  /// No description provided for @statusNoFileSelected.
  ///
  /// In en, this message translates to:
  /// **'No file selected.'**
  String get statusNoFileSelected;

  /// No description provided for @statusNoPhotosImported.
  ///
  /// In en, this message translates to:
  /// **'No local Photos items were imported.'**
  String get statusNoPhotosImported;

  /// No description provided for @photosImportFailedStatus.
  ///
  /// In en, this message translates to:
  /// **'Photos import failed: {error}'**
  String photosImportFailedStatus(String error);

  /// No description provided for @photosImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Photos import failed'**
  String get photosImportFailed;

  /// No description provided for @itemsSkippedTitle.
  ///
  /// In en, this message translates to:
  /// **'Some items were skipped'**
  String get itemsSkippedTitle;

  /// No description provided for @itemsSkippedBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected item could not be copied from Photos.} other{{count} selected items could not be copied from Photos.}} Items stored only in iCloud must be downloaded in Photos first.'**
  String itemsSkippedBody(int count);

  /// No description provided for @waitingForPhotos.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your Photos selection...'**
  String get waitingForPhotos;

  /// No description provided for @loadedLut.
  ///
  /// In en, this message translates to:
  /// **'Loaded LUT {name}.'**
  String loadedLut(String name);

  /// No description provided for @inspectingMedia.
  ///
  /// In en, this message translates to:
  /// **'Inspecting imported media...'**
  String get inspectingMedia;

  /// No description provided for @inspectingMediaProgress.
  ///
  /// In en, this message translates to:
  /// **'Inspecting imported media... {done}/{total}'**
  String inspectingMediaProgress(int done, int total);

  /// No description provided for @noSupportedMedia.
  ///
  /// In en, this message translates to:
  /// **'No supported readable media files found.'**
  String get noSupportedMedia;

  /// No description provided for @importedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Imported 1 item} other{Imported {count} items}}'**
  String importedCount(int count);

  /// No description provided for @importedSkipped.
  ///
  /// In en, this message translates to:
  /// **', skipped {count} unsupported'**
  String importedSkipped(int count);

  /// No description provided for @importNothingSaved.
  ///
  /// In en, this message translates to:
  /// **'Nothing is saved until you confirm export.'**
  String get importNothingSaved;

  /// No description provided for @preparingExport.
  ///
  /// In en, this message translates to:
  /// **'Preparing export...'**
  String get preparingExport;

  /// No description provided for @failedStatus.
  ///
  /// In en, this message translates to:
  /// **'Failed: {message}'**
  String failedStatus(String message);

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get exportFailed;

  /// No description provided for @exportCompleteEmpty.
  ///
  /// In en, this message translates to:
  /// **'Export complete. The queue is empty.'**
  String get exportCompleteEmpty;

  /// No description provided for @exportCompleteRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Export complete. 1 item remaining.} other{Export complete. {count} items remaining.}}'**
  String exportCompleteRemaining(int count);

  /// No description provided for @exportingAllMedia.
  ///
  /// In en, this message translates to:
  /// **'Exporting all selected media...'**
  String get exportingAllMedia;

  /// No description provided for @queueCancelled.
  ///
  /// In en, this message translates to:
  /// **'Queue cancelled.'**
  String get queueCancelled;

  /// No description provided for @batchFinished.
  ///
  /// In en, this message translates to:
  /// **'Batch export finished: {count} exported and removed'**
  String batchFinished(int count);

  /// No description provided for @batchFinishedFailed.
  ///
  /// In en, this message translates to:
  /// **', {count} failed'**
  String batchFinishedFailed(int count);

  /// No description provided for @exportingItem.
  ///
  /// In en, this message translates to:
  /// **'Exporting {name} on this device...'**
  String exportingItem(String name);

  /// No description provided for @chooseFilesFolderFirst.
  ///
  /// In en, this message translates to:
  /// **'Choose a Files export folder before exporting.'**
  String get chooseFilesFolderFirst;

  /// No description provided for @exportedTo.
  ///
  /// In en, this message translates to:
  /// **'Exported {file} to {destinations}.'**
  String exportedTo(String file, String destinations);

  /// No description provided for @trimStartNotNumber.
  ///
  /// In en, this message translates to:
  /// **'Trim start must be a number of seconds.'**
  String get trimStartNotNumber;

  /// No description provided for @trimEndNotNumber.
  ///
  /// In en, this message translates to:
  /// **'Trim end must be a number of seconds.'**
  String get trimEndNotNumber;

  /// No description provided for @trimStartNegative.
  ///
  /// In en, this message translates to:
  /// **'Trim start must be zero or greater.'**
  String get trimStartNegative;

  /// No description provided for @trimStartTooLate.
  ///
  /// In en, this message translates to:
  /// **'Trim start must be less than 24 hours.'**
  String get trimStartTooLate;

  /// No description provided for @trimEndBeforeStart.
  ///
  /// In en, this message translates to:
  /// **'Trim end must be after trim start.'**
  String get trimEndBeforeStart;

  /// No description provided for @trimEndTooLate.
  ///
  /// In en, this message translates to:
  /// **'Trim end must be less than 24 hours.'**
  String get trimEndTooLate;

  /// No description provided for @removedFromQueue.
  ///
  /// In en, this message translates to:
  /// **'Removed {name} from the queue.'**
  String removedFromQueue(String name);

  /// No description provided for @cannotCancelExport.
  ///
  /// In en, this message translates to:
  /// **'This export cannot be cancelled safely. It will finish shortly.'**
  String get cannotCancelExport;

  /// No description provided for @cancelRequested.
  ///
  /// In en, this message translates to:
  /// **'Cancel requested.'**
  String get cancelRequested;

  /// No description provided for @chooseExportFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose export folder'**
  String get chooseExportFolder;

  /// No description provided for @exportFolderUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The selected export folder is unavailable.'**
  String get exportFolderUnavailable;

  /// No description provided for @folderUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Folder unavailable'**
  String get folderUnavailable;

  /// No description provided for @folderUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'AquaRecover could not use the selected folder. {error}'**
  String folderUnavailableBody(String error);

  /// No description provided for @shareExportedTooltip.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Share the exported file} other{Share all {count} exported files}}'**
  String shareExportedTooltip(int count);

  /// No description provided for @shareExportsButton.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Share} other{Share all {count}}}'**
  String shareExportsButton(int count);

  /// No description provided for @videoUnavailableBuild.
  ///
  /// In en, this message translates to:
  /// **'Video export is not available in this build. Photo recovery remains available.'**
  String get videoUnavailableBuild;

  /// No description provided for @videoUnavailableIos.
  ///
  /// In en, this message translates to:
  /// **'Native iOS video export is missing from this build. Rebuild the iOS runner or run the bootstrap script, then try again.'**
  String get videoUnavailableIos;

  /// No description provided for @videoUnavailableMacos.
  ///
  /// In en, this message translates to:
  /// **'Native macOS video export is missing from this build. Rebuild the macOS runner or run the bootstrap script, then try again.'**
  String get videoUnavailableMacos;

  /// No description provided for @videoRawNeedsFfmpeg.
  ///
  /// In en, this message translates to:
  /// **'RAW video export needs an ffmpeg command-line binary, which a sandboxed macOS app cannot launch. Standard MP4 and MOV clips export natively.'**
  String get videoRawNeedsFfmpeg;

  /// No description provided for @videoWindowsNeedsFfmpeg.
  ///
  /// In en, this message translates to:
  /// **'Video export on Windows needs ffmpeg. Install it (for example with \"winget install ffmpeg\"), restart AquaRecover, and try again. Photo recovery remains available.'**
  String get videoWindowsNeedsFfmpeg;

  /// No description provided for @photosPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Photos permission was not granted.'**
  String get photosPermissionDenied;

  /// No description provided for @timelineEmptyError.
  ///
  /// In en, this message translates to:
  /// **'Add at least one photo or clip to the timeline.'**
  String get timelineEmptyError;

  /// No description provided for @tapValueToAdjust.
  ///
  /// In en, this message translates to:
  /// **'Tap a value to adjust it'**
  String get tapValueToAdjust;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @resetItem.
  ///
  /// In en, this message translates to:
  /// **'Reset {name}'**
  String resetItem(String name);

  /// No description provided for @openSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get openSourceLicenses;

  /// No description provided for @licensesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'The license list could not be loaded.'**
  String get licensesLoadFailed;

  /// No description provided for @licensesIntro.
  ///
  /// In en, this message translates to:
  /// **'AquaRecover {version} includes the following software. Select a component to read its license text.'**
  String licensesIntro(String version);

  /// No description provided for @noOtherPhotosInBatch.
  ///
  /// In en, this message translates to:
  /// **'There are no other photos in this batch.'**
  String get noOtherPhotosInBatch;

  /// No description provided for @copyEdits.
  ///
  /// In en, this message translates to:
  /// **'Copy edits'**
  String get copyEdits;

  /// No description provided for @copyEditsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the photos that should use these values.'**
  String get copyEditsSubtitle;

  /// No description provided for @copyFrom.
  ///
  /// In en, this message translates to:
  /// **'Copy from'**
  String get copyFrom;

  /// No description provided for @selectItem.
  ///
  /// In en, this message translates to:
  /// **'Select {name}'**
  String selectItem(String name);

  /// No description provided for @deselectItem.
  ///
  /// In en, this message translates to:
  /// **'Deselect {name}'**
  String deselectItem(String name);

  /// No description provided for @applyToAll.
  ///
  /// In en, this message translates to:
  /// **'Apply to all'**
  String get applyToAll;

  /// No description provided for @applyToCount.
  ///
  /// In en, this message translates to:
  /// **'Apply to {count}'**
  String applyToCount(int count);

  /// No description provided for @freeformRatio.
  ///
  /// In en, this message translates to:
  /// **'Freeform ratio'**
  String get freeformRatio;

  /// No description provided for @rotateLeft.
  ///
  /// In en, this message translates to:
  /// **'Rotate left'**
  String get rotateLeft;

  /// No description provided for @rotateRight.
  ///
  /// In en, this message translates to:
  /// **'Rotate right'**
  String get rotateRight;

  /// No description provided for @flipHorizontally.
  ///
  /// In en, this message translates to:
  /// **'Flip horizontally'**
  String get flipHorizontally;

  /// No description provided for @flipVertically.
  ///
  /// In en, this message translates to:
  /// **'Flip vertically'**
  String get flipVertically;

  /// No description provided for @resetCrop.
  ///
  /// In en, this message translates to:
  /// **'Reset crop'**
  String get resetCrop;

  /// No description provided for @straighten.
  ///
  /// In en, this message translates to:
  /// **'Straighten'**
  String get straighten;

  /// No description provided for @openToolsNamed.
  ///
  /// In en, this message translates to:
  /// **'Open {tool} tools'**
  String openToolsNamed(String tool);

  /// No description provided for @collapseToolsNamed.
  ///
  /// In en, this message translates to:
  /// **'Collapse {tool} tools'**
  String collapseToolsNamed(String tool);

  /// No description provided for @openTool.
  ///
  /// In en, this message translates to:
  /// **'Open {tool}'**
  String openTool(String tool);

  /// No description provided for @toolsNamed.
  ///
  /// In en, this message translates to:
  /// **'{tool} tools'**
  String toolsNamed(String tool);

  /// No description provided for @collapseItem.
  ///
  /// In en, this message translates to:
  /// **'Collapse {name}'**
  String collapseItem(String name);

  /// No description provided for @editingTools.
  ///
  /// In en, this message translates to:
  /// **'Editing tools'**
  String get editingTools;

  /// No description provided for @framePreview.
  ///
  /// In en, this message translates to:
  /// **'Frame preview'**
  String get framePreview;

  /// No description provided for @representativeFrame.
  ///
  /// In en, this message translates to:
  /// **'Representative frame'**
  String get representativeFrame;

  /// No description provided for @framePreviewUnavailableFormat.
  ///
  /// In en, this message translates to:
  /// **'Frame preview unavailable for this format'**
  String get framePreviewUnavailableFormat;

  /// No description provided for @previewGeneratedDuringExport.
  ///
  /// In en, this message translates to:
  /// **'Preview generated during export'**
  String get previewGeneratedDuringExport;

  /// No description provided for @compareModeFrame.
  ///
  /// In en, this message translates to:
  /// **'{mode} frame'**
  String compareModeFrame(String mode);

  /// No description provided for @exportedPhotoPreviewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Exported photo preview unavailable.'**
  String get exportedPhotoPreviewUnavailable;

  /// No description provided for @renameHint.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameHint;

  /// No description provided for @previewUnavailableFormat.
  ///
  /// In en, this message translates to:
  /// **'Preview unavailable for this format.'**
  String get previewUnavailableFormat;

  /// No description provided for @cropArea.
  ///
  /// In en, this message translates to:
  /// **'Crop area'**
  String get cropArea;

  /// No description provided for @cropAreaHint.
  ///
  /// In en, this message translates to:
  /// **'Drag an edge or corner to crop. Drag inside to move the crop and pinch to resize it.'**
  String get cropAreaHint;

  /// No description provided for @moveCropLeft.
  ///
  /// In en, this message translates to:
  /// **'Move crop left'**
  String get moveCropLeft;

  /// No description provided for @moveCropRight.
  ///
  /// In en, this message translates to:
  /// **'Move crop right'**
  String get moveCropRight;

  /// No description provided for @moveCropUp.
  ///
  /// In en, this message translates to:
  /// **'Move crop up'**
  String get moveCropUp;

  /// No description provided for @moveCropDown.
  ///
  /// In en, this message translates to:
  /// **'Move crop down'**
  String get moveCropDown;

  /// No description provided for @photoUnreadable.
  ///
  /// In en, this message translates to:
  /// **'This photo could not be read.'**
  String get photoUnreadable;

  /// No description provided for @whiteBalanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap something white or grey'**
  String get whiteBalanceSubtitle;

  /// No description provided for @whiteBalanceValues.
  ///
  /// In en, this message translates to:
  /// **'Temperature {temperature}  ·  Tint {tint}'**
  String whiteBalanceValues(String temperature, String tint);

  /// No description provided for @whiteBalanceTip.
  ///
  /// In en, this message translates to:
  /// **'Sand, a slate, or a tank work well. Drag to compare spots.'**
  String get whiteBalanceTip;

  /// No description provided for @photosTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photosTitle;

  /// No description provided for @importCount.
  ///
  /// In en, this message translates to:
  /// **'Import {count}'**
  String importCount(int count);

  /// No description provided for @openSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'Open System Settings'**
  String get openSystemSettings;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @noPhotosOrVideos.
  ///
  /// In en, this message translates to:
  /// **'No photos or videos found.'**
  String get noPhotosOrVideos;

  /// No description provided for @noneDownloadedFromPhotos.
  ///
  /// In en, this message translates to:
  /// **'None of the selected Photos items could be downloaded. Open them in Photos first, then try again.'**
  String get noneDownloadedFromPhotos;

  /// No description provided for @itemsNotDownloaded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected item could not be downloaded from Photos.} other{{count} selected items could not be downloaded from Photos.}} {remaining, plural, =1{The remaining 1 will be imported.} other{The remaining {remaining} will be imported.}}'**
  String itemsNotDownloaded(int count, int remaining);

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @photosAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'Photos access is turned off. Allow AquaRecover to access your photo library in System Settings, then try again.'**
  String get photosAccessDenied;

  /// No description provided for @photosAccessRestricted.
  ///
  /// In en, this message translates to:
  /// **'Photos access is restricted by the system or device settings.'**
  String get photosAccessRestricted;

  /// No description provided for @photosAccessNotDetermined.
  ///
  /// In en, this message translates to:
  /// **'Photos access has not been granted yet. Try again to show the system permission request.'**
  String get photosAccessNotDetermined;

  /// No description provided for @photosAccessAvailable.
  ///
  /// In en, this message translates to:
  /// **'Photos access is available.'**
  String get photosAccessAvailable;

  /// No description provided for @photosItemNotLocal.
  ///
  /// In en, this message translates to:
  /// **'The selected Photos item is not available locally. Open it in Photos to download the original from iCloud, then import it again.'**
  String get photosItemNotLocal;

  /// No description provided for @photosItemUnreadable.
  ///
  /// In en, this message translates to:
  /// **'The selected Photos item could not be read from local storage. Choose another item or download the original first.'**
  String get photosItemUnreadable;

  /// No description provided for @photosPickerFailed.
  ///
  /// In en, this message translates to:
  /// **'The Photos picker failed.'**
  String get photosPickerFailed;

  /// No description provided for @presetStrength.
  ///
  /// In en, this message translates to:
  /// **'Preset strength'**
  String get presetStrength;

  /// No description provided for @presetStrengthNoneHelp.
  ///
  /// In en, this message translates to:
  /// **'None leaves the image unchanged. Choose another preset to adjust its strength.'**
  String get presetStrengthNoneHelp;

  /// No description provided for @presetStrengthHelp.
  ///
  /// In en, this message translates to:
  /// **'Scales the selected preset while keeping later manual adjustments.'**
  String get presetStrengthHelp;

  /// No description provided for @presetSummary.
  ///
  /// In en, this message translates to:
  /// **'{preset}: {help}'**
  String presetSummary(String preset, String help);

  /// No description provided for @waterBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue water'**
  String get waterBlue;

  /// No description provided for @waterGreen.
  ///
  /// In en, this message translates to:
  /// **'Green water'**
  String get waterGreen;

  /// No description provided for @waterNeutral.
  ///
  /// In en, this message translates to:
  /// **'Little color cast'**
  String get waterNeutral;

  /// No description provided for @suggestionSemantics.
  ///
  /// In en, this message translates to:
  /// **'{water}. Suggested {preset} at {strength} percent.'**
  String suggestionSemantics(String water, String preset, int strength);

  /// No description provided for @suggestionTitle.
  ///
  /// In en, this message translates to:
  /// **'{water}: {preset} {strength}%'**
  String suggestionTitle(String water, String preset, int strength);

  /// No description provided for @applied.
  ///
  /// In en, this message translates to:
  /// **'Applied'**
  String get applied;

  /// No description provided for @presetChipSemantics.
  ///
  /// In en, this message translates to:
  /// **'{preset} preset'**
  String presetChipSemantics(String preset);

  /// No description provided for @presetChipSuggestedSemantics.
  ///
  /// In en, this message translates to:
  /// **'{preset} preset, suggested'**
  String presetChipSuggestedSemantics(String preset);

  /// No description provided for @reasonArtificialLight.
  ///
  /// In en, this message translates to:
  /// **'Colors are close to neutral and highlights clip, which is typical for strobe or video-light shots.'**
  String get reasonArtificialLight;

  /// No description provided for @reasonRedFilter.
  ///
  /// In en, this message translates to:
  /// **'Red is mostly present but slightly low, as with a red dive filter.'**
  String get reasonRedFilter;

  /// No description provided for @reasonNatural.
  ///
  /// In en, this message translates to:
  /// **'Little red is missing, so only a gentle correction.'**
  String get reasonNatural;

  /// No description provided for @reasonGreenWater.
  ///
  /// In en, this message translates to:
  /// **'Green dominates blue (blue/green {ratio}), typical for plankton-rich or lake water.'**
  String reasonGreenWater(String ratio);

  /// No description provided for @reasonDeep.
  ///
  /// In en, this message translates to:
  /// **'Almost no red remains and the scene is dark, which points to depth.'**
  String get reasonDeep;

  /// No description provided for @reasonShallow.
  ///
  /// In en, this message translates to:
  /// **'Bright, moderately blue scene, typical for shallow water.'**
  String get reasonShallow;

  /// No description provided for @reasonAuto.
  ///
  /// In en, this message translates to:
  /// **'Typical blue water cast; the balanced default fits.'**
  String get reasonAuto;

  /// No description provided for @queueLocked.
  ///
  /// In en, this message translates to:
  /// **'Queue changes are locked until the current export finishes.'**
  String get queueLocked;

  /// No description provided for @noSelectedMedia.
  ///
  /// In en, this message translates to:
  /// **'No selected media.'**
  String get noSelectedMedia;

  /// No description provided for @selection.
  ///
  /// In en, this message translates to:
  /// **'Selection'**
  String get selection;

  /// No description provided for @itemsInQueue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item in the queue} other{{count} items in the queue}}'**
  String itemsInQueue(int count);

  /// No description provided for @itemWithStatus.
  ///
  /// In en, this message translates to:
  /// **'{name}, {status}'**
  String itemWithStatus(String name, String status);

  /// No description provided for @rawVideoSettings.
  ///
  /// In en, this message translates to:
  /// **'RAW video settings'**
  String get rawVideoSettings;

  /// No description provided for @width.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get width;

  /// No description provided for @height.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get height;

  /// No description provided for @frameRate.
  ///
  /// In en, this message translates to:
  /// **'Frame rate'**
  String get frameRate;

  /// No description provided for @rawVideoNumbersRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter whole numbers for width and height and a number for the frame rate.'**
  String get rawVideoNumbersRequired;

  /// No description provided for @rawVideoTooSmall.
  ///
  /// In en, this message translates to:
  /// **'RAW video dimensions are too small.'**
  String get rawVideoTooSmall;

  /// No description provided for @rawVideoTooLarge.
  ///
  /// In en, this message translates to:
  /// **'RAW video dimensions must be at most {max}x{max}.'**
  String rawVideoTooLarge(int max);

  /// No description provided for @rawVideoTooManyPixels.
  ///
  /// In en, this message translates to:
  /// **'RAW video frames are too large. Maximum is {max} pixels per frame.'**
  String rawVideoTooManyPixels(int max);

  /// No description provided for @rawVideoFrameRateRange.
  ///
  /// In en, this message translates to:
  /// **'Frame rate must be between {min} and {max} fps.'**
  String rawVideoFrameRateRange(String min, String max);

  /// No description provided for @renderingPreview.
  ///
  /// In en, this message translates to:
  /// **'Rendering preview'**
  String get renderingPreview;

  /// No description provided for @previewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Preview unavailable'**
  String get previewUnavailable;

  /// No description provided for @videoFramePreviewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Video frame preview unavailable.'**
  String get videoFramePreviewUnavailable;

  /// No description provided for @videoPreviewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Video preview unavailable.'**
  String get videoPreviewUnavailable;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// A depth in meters; value is already formatted.
  ///
  /// In en, this message translates to:
  /// **'{value} m'**
  String metersValue(String value);

  /// No description provided for @celsiusValue.
  ///
  /// In en, this message translates to:
  /// **'{value} °C'**
  String celsiusValue(String value);

  /// No description provided for @minutesValue.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String minutesValue(int count);

  /// No description provided for @logbook.
  ///
  /// In en, this message translates to:
  /// **'Logbook'**
  String get logbook;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @importAndExport.
  ///
  /// In en, this message translates to:
  /// **'Import and export'**
  String get importAndExport;

  /// No description provided for @addDive.
  ///
  /// In en, this message translates to:
  /// **'Add dive'**
  String get addDive;

  /// No description provided for @dives.
  ///
  /// In en, this message translates to:
  /// **'Dives'**
  String get dives;

  /// No description provided for @map.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get map;

  /// No description provided for @noDivesYet.
  ///
  /// In en, this message translates to:
  /// **'No dives yet'**
  String get noDivesYet;

  /// No description provided for @noDivesYetBody.
  ///
  /// In en, this message translates to:
  /// **'Import a UDDF log from your dive computer or Subsurface, or add a dive by hand. Your logbook stays on this device.'**
  String get noDivesYetBody;

  /// No description provided for @importLog.
  ///
  /// In en, this message translates to:
  /// **'Import log'**
  String get importLog;

  /// No description provided for @linkedMediaCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 linked media item} other{{count} linked media}}'**
  String linkedMediaCount(int count);

  /// No description provided for @noSitePositions.
  ///
  /// In en, this message translates to:
  /// **'No dive site has a position yet. Add latitude and longitude to a dive to see it here.'**
  String get noSitePositions;

  /// No description provided for @diveSite.
  ///
  /// In en, this message translates to:
  /// **'Dive site'**
  String get diveSite;

  /// No description provided for @diveCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 dive} other{{count} dives}}'**
  String diveCount(int count);

  /// No description provided for @importUddfLog.
  ///
  /// In en, this message translates to:
  /// **'Import UDDF log'**
  String get importUddfLog;

  /// No description provided for @linkPhotosByTime.
  ///
  /// In en, this message translates to:
  /// **'Link photos by capture time'**
  String get linkPhotosByTime;

  /// No description provided for @exportGpx.
  ///
  /// In en, this message translates to:
  /// **'Export GPX'**
  String get exportGpx;

  /// No description provided for @exportUddf.
  ///
  /// In en, this message translates to:
  /// **'Export UDDF'**
  String get exportUddf;

  /// No description provided for @exportGeoJson.
  ///
  /// In en, this message translates to:
  /// **'Export GeoJSON'**
  String get exportGeoJson;

  /// No description provided for @logImported.
  ///
  /// In en, this message translates to:
  /// **'Log imported'**
  String get logImported;

  /// No description provided for @logImportedBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Every dive in this log is already in your logbook.} =1{1 new dive was added.} other{{count} new dives were added.}}'**
  String logImportedBody(int count);

  /// No description provided for @cannotImportFile.
  ///
  /// In en, this message translates to:
  /// **'Can’t import this file'**
  String get cannotImportFile;

  /// No description provided for @noDiveTimes.
  ///
  /// In en, this message translates to:
  /// **'No dive times'**
  String get noDiveTimes;

  /// No description provided for @noDiveTimesBody.
  ///
  /// In en, this message translates to:
  /// **'Dives need a start time and duration to match photos.'**
  String get noDiveTimesBody;

  /// No description provided for @photosLinked.
  ///
  /// In en, this message translates to:
  /// **'Photos linked'**
  String get photosLinked;

  /// No description provided for @photosLinkedBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No new photos or videos were taken during your dives.} other{{count} photos and videos were linked to their dives.}}'**
  String photosLinkedBody(int count);

  /// No description provided for @cannotReadPhotoLibrary.
  ///
  /// In en, this message translates to:
  /// **'Can’t read the photo library'**
  String get cannotReadPhotoLibrary;

  /// No description provided for @editDive.
  ///
  /// In en, this message translates to:
  /// **'Edit dive'**
  String get editDive;

  /// No description provided for @newDive.
  ///
  /// In en, this message translates to:
  /// **'New dive'**
  String get newDive;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @diveNumber.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get diveNumber;

  /// No description provided for @site.
  ///
  /// In en, this message translates to:
  /// **'Site'**
  String get site;

  /// No description provided for @latitude.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get latitude;

  /// No description provided for @longitude.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get longitude;

  /// No description provided for @maxDepthMeters.
  ///
  /// In en, this message translates to:
  /// **'Max depth (m)'**
  String get maxDepthMeters;

  /// No description provided for @durationMinutes.
  ///
  /// In en, this message translates to:
  /// **'Duration (min)'**
  String get durationMinutes;

  /// No description provided for @waterTemperatureCelsius.
  ///
  /// In en, this message translates to:
  /// **'Water temperature (°C)'**
  String get waterTemperatureCelsius;

  /// No description provided for @buddy.
  ///
  /// In en, this message translates to:
  /// **'Buddy'**
  String get buddy;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @deleteDive.
  ///
  /// In en, this message translates to:
  /// **'Delete dive'**
  String get deleteDive;

  /// No description provided for @dateAndTime.
  ///
  /// In en, this message translates to:
  /// **'Date and time'**
  String get dateAndTime;

  /// No description provided for @dateAndTimeValue.
  ///
  /// In en, this message translates to:
  /// **'Date and time, {date}'**
  String dateAndTimeValue(String date);

  /// No description provided for @checkPosition.
  ///
  /// In en, this message translates to:
  /// **'Check the position'**
  String get checkPosition;

  /// No description provided for @checkPositionBody.
  ///
  /// In en, this message translates to:
  /// **'Enter both latitude (−90 to 90) and longitude (−180 to 180) in decimal degrees, or leave both empty.'**
  String get checkPositionBody;

  /// No description provided for @deleteDiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this dive?'**
  String get deleteDiveTitle;

  /// No description provided for @deleteDiveBody.
  ///
  /// In en, this message translates to:
  /// **'Its photos and videos stay where they are; only the log entry is removed.'**
  String get deleteDiveBody;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// No description provided for @position.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get position;

  /// No description provided for @maxDepth.
  ///
  /// In en, this message translates to:
  /// **'Max depth'**
  String get maxDepth;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// No description provided for @waterTemperature.
  ///
  /// In en, this message translates to:
  /// **'Water temperature'**
  String get waterTemperature;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @depthReadings.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 depth reading} other{{count} depth readings}}'**
  String depthReadings(int count);

  /// No description provided for @photosAndVideos.
  ///
  /// In en, this message translates to:
  /// **'Photos and videos'**
  String get photosAndVideos;

  /// No description provided for @nothingLinked.
  ///
  /// In en, this message translates to:
  /// **'Nothing linked yet. Linked media stays where it is; the logbook never copies it.'**
  String get nothingLinked;

  /// No description provided for @makeMovieFromDive.
  ///
  /// In en, this message translates to:
  /// **'Make a movie from this dive'**
  String get makeMovieFromDive;

  /// No description provided for @addPhotosAndVideos.
  ///
  /// In en, this message translates to:
  /// **'Add photos and videos'**
  String get addPhotosAndVideos;

  /// No description provided for @findInPhotos.
  ///
  /// In en, this message translates to:
  /// **'Find in Photos'**
  String get findInPhotos;

  /// No description provided for @mediaDepthSuffix.
  ///
  /// In en, this message translates to:
  /// **', {depth} deep'**
  String mediaDepthSuffix(String depth);

  /// No description provided for @removeFromDive.
  ///
  /// In en, this message translates to:
  /// **'Remove from dive'**
  String get removeFromDive;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @diveMediaLinkedBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No new photos or videos from this dive were found.} =1{1 photo or video was linked.} other{{count} photos and videos were linked.}}'**
  String diveMediaLinkedBody(int count);

  /// No description provided for @mediaNotFound.
  ///
  /// In en, this message translates to:
  /// **'Media not found'**
  String get mediaNotFound;

  /// No description provided for @mediaNotFoundBody.
  ///
  /// In en, this message translates to:
  /// **'None of the linked photos or videos can be opened. They may have been moved or deleted.'**
  String get mediaNotFoundBody;

  /// No description provided for @diveSiteNamed.
  ///
  /// In en, this message translates to:
  /// **'Dive site {name}'**
  String diveSiteNamed(String name);

  /// No description provided for @osmAttributionSemantics.
  ///
  /// In en, this message translates to:
  /// **'Map data © OpenStreetMap contributors. Show license.'**
  String get osmAttributionSemantics;

  /// No description provided for @osmAttribution.
  ///
  /// In en, this message translates to:
  /// **'© OpenStreetMap contributors'**
  String get osmAttribution;

  /// No description provided for @diveTitleUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Dive'**
  String get diveTitleUnnamed;

  /// No description provided for @diveTitleNumber.
  ///
  /// In en, this message translates to:
  /// **'Dive {number}'**
  String diveTitleNumber(int number);

  /// No description provided for @diveTitleNumberSite.
  ///
  /// In en, this message translates to:
  /// **'#{number} {site}'**
  String diveTitleNumberSite(int number, String site);

  /// No description provided for @coordinatePair.
  ///
  /// In en, this message translates to:
  /// **'{latitude}, {longitude}'**
  String coordinatePair(String latitude, String longitude);

  /// No description provided for @localExportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Local Exports'**
  String get localExportsTitle;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @exportsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Exports could not be loaded.'**
  String get exportsLoadFailed;

  /// No description provided for @noLocalExports.
  ///
  /// In en, this message translates to:
  /// **'No local exports yet.'**
  String get noLocalExports;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get deselectAll;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @localExportCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 local export} other{{count} local exports}}'**
  String localExportCount(int count);

  /// No description provided for @deleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get deleteAll;

  /// No description provided for @deleteCount.
  ///
  /// In en, this message translates to:
  /// **'Delete {count}'**
  String deleteCount(int count);

  /// No description provided for @shareSelectedExports.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Share the selected export} other{Share the selected exports}}'**
  String shareSelectedExports(int count);

  /// No description provided for @shareCount.
  ///
  /// In en, this message translates to:
  /// **'Share {count}'**
  String shareCount(int count);

  /// No description provided for @deleteAllExportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete all local exports?'**
  String get deleteAllExportsTitle;

  /// No description provided for @deleteExportsTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete 1 export?} other{Delete {count} exports?}}'**
  String deleteExportsTitle(int count);

  /// No description provided for @deleteExportsBody.
  ///
  /// In en, this message translates to:
  /// **'The local files and their settings sidecars will be deleted. Imported originals and copies in Photos are not affected.'**
  String get deleteExportsBody;

  /// No description provided for @someExportsNotDeleted.
  ///
  /// In en, this message translates to:
  /// **'Some exports could not be deleted'**
  String get someExportsNotDeleted;

  /// No description provided for @someExportsNotDeletedBody.
  ///
  /// In en, this message translates to:
  /// **'{failures} of {count} files may have been moved or are currently unavailable.'**
  String someExportsNotDeletedBody(int failures, int count);

  /// No description provided for @shareExport.
  ///
  /// In en, this message translates to:
  /// **'Share export'**
  String get shareExport;

  /// No description provided for @deleteExport.
  ///
  /// In en, this message translates to:
  /// **'Delete export'**
  String get deleteExport;

  /// No description provided for @previewUnavailableShort.
  ///
  /// In en, this message translates to:
  /// **'Preview unavailable.'**
  String get previewUnavailableShort;

  /// No description provided for @deleteExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete local export?'**
  String get deleteExportTitle;

  /// No description provided for @deleteExportBody.
  ///
  /// In en, this message translates to:
  /// **'The local file and its settings sidecar will be deleted. The imported original and any copy in Photos are not affected.'**
  String get deleteExportBody;

  /// No description provided for @exportNotDeleted.
  ///
  /// In en, this message translates to:
  /// **'Export could not be deleted'**
  String get exportNotDeleted;

  /// No description provided for @exportNotDeletedBody.
  ///
  /// In en, this message translates to:
  /// **'The file may have been moved or is currently unavailable.'**
  String get exportNotDeletedBody;

  /// No description provided for @couldNotShare.
  ///
  /// In en, this message translates to:
  /// **'Could not share'**
  String get couldNotShare;

  /// No description provided for @shareSheetUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The share sheet could not be opened on this device. The export is still in Local Exports.'**
  String get shareSheetUnavailable;

  /// No description provided for @exportedFileGone.
  ///
  /// In en, this message translates to:
  /// **'The exported file is no longer available. It may have been deleted from Local Exports.'**
  String get exportedFileGone;

  /// No description provided for @exportedFilesGone.
  ///
  /// In en, this message translates to:
  /// **'The exported files are no longer available. They may have been deleted from Local Exports.'**
  String get exportedFilesGone;

  /// No description provided for @previewSize.
  ///
  /// In en, this message translates to:
  /// **'Preview size'**
  String get previewSize;

  /// No description provided for @dragToResizePreview.
  ///
  /// In en, this message translates to:
  /// **'Drag to resize preview'**
  String get dragToResizePreview;

  /// No description provided for @resetPreviewSize.
  ///
  /// In en, this message translates to:
  /// **'Reset preview size'**
  String get resetPreviewSize;

  /// No description provided for @appIconLabel.
  ///
  /// In en, this message translates to:
  /// **'AquaRecover app icon'**
  String get appIconLabel;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @tourWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore color with a clear workflow'**
  String get tourWelcomeTitle;

  /// No description provided for @tourWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'AquaRecover keeps the process simple: choose media, refine the result, then decide where to export it.'**
  String get tourWelcomeBody;

  /// No description provided for @tourImportTitle.
  ///
  /// In en, this message translates to:
  /// **'One photo or a complete batch'**
  String get tourImportTitle;

  /// No description provided for @tourImportBody.
  ///
  /// In en, this message translates to:
  /// **'A single selection opens in the editor. Select several items and they stay together in a queue you can review at any time.'**
  String get tourImportBody;

  /// No description provided for @tourEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit, inspect, and compare'**
  String get tourEditTitle;

  /// No description provided for @tourEditBody.
  ///
  /// In en, this message translates to:
  /// **'Start with a preset, then fine-tune adjustments, crop, and LUT. Tap a value bubble to adjust it; Reset restores the preset value.'**
  String get tourEditBody;

  /// No description provided for @tourExportTitle.
  ///
  /// In en, this message translates to:
  /// **'You choose when and where to save'**
  String get tourExportTitle;

  /// No description provided for @tourExportBody.
  ///
  /// In en, this message translates to:
  /// **'Importing and editing never create a saved copy. On export, choose one or more destinations for the finished media.'**
  String get tourExportBody;

  /// No description provided for @previousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get previousPage;

  /// No description provided for @startEditing.
  ///
  /// In en, this message translates to:
  /// **'Start editing'**
  String get startEditing;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @tutorialPageOf.
  ///
  /// In en, this message translates to:
  /// **'Tutorial page {page} of {count}'**
  String tutorialPageOf(int page, int count);

  /// No description provided for @onDevicePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Your media is processed on this device. AquaRecover does not upload it to a service.'**
  String get onDevicePrivacy;

  /// No description provided for @onePhoto.
  ///
  /// In en, this message translates to:
  /// **'One photo'**
  String get onePhoto;

  /// No description provided for @batch.
  ///
  /// In en, this message translates to:
  /// **'Batch'**
  String get batch;

  /// No description provided for @tourOnePhotoHint.
  ///
  /// In en, this message translates to:
  /// **'The photo opens directly in the editor.'**
  String get tourOnePhotoHint;

  /// No description provided for @tourBatchHint.
  ///
  /// In en, this message translates to:
  /// **'Three items are ready in one editable queue.'**
  String get tourBatchHint;

  /// No description provided for @tourPresetsHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a starting look.'**
  String get tourPresetsHint;

  /// No description provided for @tourAdjustHint.
  ///
  /// In en, this message translates to:
  /// **'Fine-tune each value.'**
  String get tourAdjustHint;

  /// No description provided for @tourCropHint.
  ///
  /// In en, this message translates to:
  /// **'Crop, rotate, and flip.'**
  String get tourCropHint;

  /// No description provided for @tourLutHint.
  ///
  /// In en, this message translates to:
  /// **'Apply a finishing LUT.'**
  String get tourLutHint;

  /// No description provided for @originalSlashEdited.
  ///
  /// In en, this message translates to:
  /// **'Original / Edited'**
  String get originalSlashEdited;

  /// No description provided for @tourCompareHint.
  ///
  /// In en, this message translates to:
  /// **'Try Split, or press and hold the preview for the original.'**
  String get tourCompareHint;

  /// No description provided for @editorToolNamed.
  ///
  /// In en, this message translates to:
  /// **'{tool} editor tool'**
  String editorToolNamed(String tool);

  /// No description provided for @exportDestinationNamed.
  ///
  /// In en, this message translates to:
  /// **'{destination} export destination'**
  String exportDestinationNamed(String destination);

  /// No description provided for @tourExportCallout.
  ///
  /// In en, this message translates to:
  /// **'Only a confirmed export writes the finished file. Completed batch items then leave the queue.'**
  String get tourExportCallout;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
