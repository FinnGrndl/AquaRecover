import '../core/timeline/timeline_project.dart';
import 'app_localizations.dart';

// The timeline models keep English labels for logs and the MCP server. The
// movie editor shows these localized ones instead.

extension EffectCategoryL10n on EffectCategory {
  String labelIn(AppLocalizations l10n) => switch (this) {
    EffectCategory.look => l10n.effectCategoryLook,
    EffectCategory.lens => l10n.effectCategoryLens,
    EffectCategory.underwater => l10n.effectCategoryUnderwater,
    EffectCategory.motion => l10n.effectCategoryMotion,
  };
}

extension EffectTypeL10n on EffectType {
  String labelIn(AppLocalizations l10n) => switch (this) {
    EffectType.mono => l10n.effectMono,
    EffectType.sepia => l10n.effectSepia,
    EffectType.cyanotype => l10n.effectCyanotype,
    EffectType.deepBlue => l10n.effectDeepBlue,
    EffectType.vivid => l10n.effectVivid,
    EffectType.faded => l10n.effectFaded,
    EffectType.softFocus => l10n.effectSoftFocus,
    EffectType.clarity => l10n.effectClarity,
    EffectType.grain => l10n.effectGrain,
    EffectType.vignette => l10n.effectVignette,
    EffectType.cinemaBars => l10n.effectCinemaBars,
    EffectType.sunRays => l10n.effectSunRays,
    EffectType.caustics => l10n.effectCaustics,
    EffectType.strobe => l10n.effectStrobe,
    EffectType.swell => l10n.effectSwell,
    EffectType.drift => l10n.effectDrift,
  };
}

extension TimelineAspectL10n on TimelineAspect {
  String labelIn(AppLocalizations l10n) => switch (this) {
    TimelineAspect.landscape => l10n.aspectLandscape,
    TimelineAspect.portrait => l10n.aspectPortrait,
    TimelineAspect.square => l10n.aspectSquare,
    TimelineAspect.vertical45 => l10n.aspectPortrait45,
  };
}

extension FadeColorL10n on FadeColor {
  String labelIn(AppLocalizations l10n) => switch (this) {
    FadeColor.black => l10n.fadeColorBlack,
    FadeColor.white => l10n.fadeColorWhite,
    FadeColor.deepBlue => l10n.fadeColorDeepBlue,
  };
}

extension OverlayAnimationL10n on OverlayAnimation {
  String labelIn(AppLocalizations l10n) => switch (this) {
    OverlayAnimation.none => l10n.animationNone,
    OverlayAnimation.fade => l10n.animationFade,
    OverlayAnimation.slideUp => l10n.animationSlideUp,
    OverlayAnimation.pop => l10n.animationPop,
  };
}

extension TitleStyleL10n on TitleStyle {
  String labelIn(AppLocalizations l10n) => switch (this) {
    TitleStyle.classic => l10n.titleStyleClassic,
    TitleStyle.boldBox => l10n.titleStyleBox,
    TitleStyle.outline => l10n.titleStyleOutline,
    TitleStyle.caption => l10n.titleStyleCaption,
    TitleStyle.diveStamp => l10n.titleStyleDiveStamp,
  };
}

extension AudioRoleL10n on AudioRole {
  String labelIn(AppLocalizations l10n) => switch (this) {
    AudioRole.music => l10n.audioRoleMusic,
    AudioRole.voiceover => l10n.audioRoleVoiceover,
    AudioRole.sound => l10n.audioRoleSound,
    AudioRole.extracted => l10n.audioRoleExtracted,
  };
}
