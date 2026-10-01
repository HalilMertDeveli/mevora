import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Mevora's icon vocabulary.
///
/// One family — Phosphor (MIT) — used in two weights with one rule:
/// **Regular** for anything at rest, **Fill** for the selected / active /
/// affirmed state of the same concept (a selected tab, a liked heart, a
/// verified seal). Never mix in Material `Icons`.
///
/// Name icons by what they *mean* in Mevora, not by what they depict, so a
/// concept keeps one glyph everywhere.
abstract final class MevoraIcons {
  // —— Navigation ——————————————————————————————————————————————————————
  static const IconData discover = PhosphorIconsRegular.compass;
  static const IconData discoverActive = PhosphorIconsFill.compass;
  static const IconData matches = PhosphorIconsRegular.chatsCircle;
  static const IconData matchesActive = PhosphorIconsFill.chatsCircle;
  static const IconData music = PhosphorIconsRegular.musicNotes;
  static const IconData musicActive = PhosphorIconsFill.musicNotes;
  static const IconData profile = PhosphorIconsRegular.user;
  static const IconData profileActive = PhosphorIconsFill.user;
  static const IconData settings = PhosphorIconsRegular.gearSix;

  static const IconData back = PhosphorIconsRegular.arrowLeft;
  static const IconData forward = PhosphorIconsRegular.arrowRight;
  static const IconData chevronRight = PhosphorIconsRegular.caretRight;
  static const IconData chevronLeft = PhosphorIconsRegular.caretLeft;
  static const IconData chevronDown = PhosphorIconsRegular.caretDown;
  static const IconData chevronUp = PhosphorIconsRegular.caretUp;
  static const IconData close = PhosphorIconsRegular.x;
  static const IconData more = PhosphorIconsRegular.dotsThree;
  static const IconData dragHandle = PhosphorIconsRegular.dotsSixVertical;
  static const IconData moreVertical = PhosphorIconsRegular.dotsThreeVertical;
  static const IconData externalLink = PhosphorIconsRegular.arrowUpRight;

  // —— Mevora concepts —————————————————————————————————————————————————
  /// "Why you fit" — two overlapping circles.
  static const IconData compatibility = PhosphorIconsRegular.intersect;
  static const IconData compatibilityActive = PhosphorIconsFill.intersect;
  static const IconData humor = PhosphorIconsRegular.maskHappy;
  static const IconData humorActive = PhosphorIconsFill.maskHappy;
  static const IconData like = PhosphorIconsRegular.heart;
  static const IconData liked = PhosphorIconsFill.heart;
  static const IconData pass = PhosphorIconsRegular.x;
  static const IconData unmatch = PhosphorIconsRegular.heartBreak;
  static const IconData superLike = PhosphorIconsFill.star;
  static const IconData star = PhosphorIconsRegular.star;
  static const IconData boost = PhosphorIconsRegular.lightning;
  static const IconData boostActive = PhosphorIconsFill.lightning;
  static const IconData premium = PhosphorIconsRegular.crownSimple;
  static const IconData premiumActive = PhosphorIconsFill.crownSimple;

  /// Daily streak — the ember of a returning habit.
  static const IconData streak = PhosphorIconsFill.fire;
  static const IconData verified = PhosphorIconsFill.sealCheck;
  static const IconData verify = PhosphorIconsRegular.sealCheck;
  static const IconData safety = PhosphorIconsRegular.shieldCheck;

  /// Face Anchor — this one photo is the member. Not the seal above, which is
  /// about identity verification of the account: different question, different
  /// mark.
  static const IconData faceAnchor = PhosphorIconsFill.userCircleCheck;
  static const IconData faceAnchorVerify = PhosphorIconsRegular.userFocus;
  static const IconData privacy = PhosphorIconsRegular.shield;
  static const IconData insight = PhosphorIconsRegular.sparkle;
  static const IconData questions = PhosphorIconsRegular.chatCircleDots;
  static const IconData quote = PhosphorIconsRegular.quotes;
  static const IconData people = PhosphorIconsRegular.users;
  static const IconData message = PhosphorIconsRegular.chatCircle;
  static const IconData send = PhosphorIconsFill.paperPlaneRight;

  // —— Music ————————————————————————————————————————————————————————————
  static const IconData track = PhosphorIconsRegular.musicNote;
  static const IconData playlist = PhosphorIconsRegular.playlist;
  static const IconData album = PhosphorIconsRegular.vinylRecord;
  static const IconData headphones = PhosphorIconsRegular.headphones;
  static const IconData waveform = PhosphorIconsRegular.waveform;
  static const IconData play = PhosphorIconsFill.play;
  static const IconData pause = PhosphorIconsFill.pause;
  static const IconData skip = PhosphorIconsRegular.skipForward;
  static const IconData volumeOn = PhosphorIconsRegular.speakerHigh;
  static const IconData volumeOff = PhosphorIconsRegular.speakerSlash;

  // —— Humor ratings (1 = not funny … 5 = very funny) ————————————————
  static const IconData ratingNotFunny = PhosphorIconsRegular.smileySad;
  static const IconData ratingMeh = PhosphorIconsRegular.smileyMeh;
  static const IconData ratingNeutral = PhosphorIconsRegular.smileyBlank;
  static const IconData ratingFunny = PhosphorIconsRegular.smiley;
  static const IconData ratingVeryFunny = PhosphorIconsRegular.smileyWink;

  // —— Actions —————————————————————————————————————————————————————————
  static const IconData add = PhosphorIconsRegular.plus;
  static const IconData edit = PhosphorIconsRegular.pencilSimple;
  static const IconData editNote = PhosphorIconsRegular.notePencil;
  static const IconData delete = PhosphorIconsRegular.trash;
  static const IconData export = PhosphorIconsRegular.downloadSimple;
  static const IconData search = PhosphorIconsRegular.magnifyingGlass;
  static const IconData searchEmpty = PhosphorIconsRegular.binoculars;
  static const IconData filters = PhosphorIconsRegular.slidersHorizontal;
  static const IconData refresh = PhosphorIconsRegular.arrowClockwise;
  static const IconData undo = PhosphorIconsRegular.arrowCounterClockwise;
  static const IconData check = PhosphorIconsRegular.check;
  static const IconData checkAll = PhosphorIconsRegular.checks;
  static const IconData success = PhosphorIconsFill.checkCircle;
  static const IconData successOutline = PhosphorIconsRegular.checkCircle;
  static const IconData report = PhosphorIconsRegular.flag;
  static const IconData block = PhosphorIconsRegular.prohibit;
  static const IconData attach = PhosphorIconsRegular.paperclip;
  static const IconData signOut = PhosphorIconsRegular.signOut;
  static const IconData dropdown = PhosphorIconsRegular.caretDown;

  // —— Media ———————————————————————————————————————————————————————————
  static const IconData camera = PhosphorIconsRegular.camera;
  static const IconData addPhoto = PhosphorIconsRegular.cameraPlus;
  static const IconData cameraSwitch = PhosphorIconsRegular.cameraRotate;
  static const IconData photos = PhosphorIconsRegular.images;
  static const IconData photo = PhosphorIconsRegular.image;
  static const IconData photoBroken = PhosphorIconsRegular.imageBroken;
  static const IconData video = PhosphorIconsRegular.videoCamera;
  static const IconData videoOff = PhosphorIconsRegular.videoCameraSlash;
  static const IconData mic = PhosphorIconsRegular.microphone;
  static const IconData micOff = PhosphorIconsRegular.microphoneSlash;
  static const IconData callEnd = PhosphorIconsFill.phoneDisconnect;

  // —— Account & system ————————————————————————————————————————————————
  static const IconData email = PhosphorIconsRegular.envelopeSimple;
  static const IconData emailRead = PhosphorIconsRegular.envelopeOpen;
  static const IconData phone = PhosphorIconsRegular.phone;
  static const IconData device = PhosphorIconsRegular.deviceMobile;
  static const IconData lock = PhosphorIconsRegular.lockSimple;
  static const IconData locked = PhosphorIconsFill.lockSimple;
  static const IconData visible = PhosphorIconsRegular.eye;
  static const IconData hidden = PhosphorIconsRegular.eyeSlash;
  static const IconData notifications = PhosphorIconsRegular.bell;
  static const IconData location = PhosphorIconsRegular.mapPin;
  static const IconData locationOff = PhosphorIconsRegular.mapPinLine;
  static const IconData calendar = PhosphorIconsRegular.calendarBlank;
  static const IconData support = PhosphorIconsRegular.lifebuoy;
  static const IconData store = PhosphorIconsRegular.storefront;
  static const IconData info = PhosphorIconsRegular.info;
  static const IconData error = PhosphorIconsRegular.warningCircle;
  static const IconData offline = PhosphorIconsRegular.cloudSlash;
  static const IconData pending = PhosphorIconsRegular.hourglassMedium;
  static const IconData empty = PhosphorIconsRegular.hourglassSimple;
  static const IconData dot = PhosphorIconsFill.circle;

  // —— Brands (sign-in providers only) ———————————————————————————————
  static const IconData apple = PhosphorIconsFill.appleLogo;
  static const IconData google = PhosphorIconsBold.googleLogo;
  static const IconData spotify = PhosphorIconsFill.spotifyLogo;

  // —— Interests ————————————————————————————————————————————————————————
  static const IconData sports = PhosphorIconsRegular.soccerBall;
  static const IconData gaming = PhosphorIconsRegular.gameController;
  static const IconData cooking = PhosphorIconsRegular.cookingPot;
  static const IconData shopping = PhosphorIconsRegular.shoppingBag;
  static const IconData wellbeing = PhosphorIconsRegular.flowerLotus;
  static const IconData science = PhosphorIconsRegular.flask;
  static const IconData food = PhosphorIconsRegular.forkKnife;
  static const IconData pets = PhosphorIconsRegular.pawPrint;
  static const IconData outdoors = PhosphorIconsRegular.tree;
  static const IconData art = PhosphorIconsRegular.palette;
  static const IconData nightlife = PhosphorIconsRegular.martini;
  static const IconData film = PhosphorIconsRegular.filmSlate;
  static const IconData books = PhosphorIconsRegular.bookOpen;
  static const IconData fitness = PhosphorIconsRegular.barbell;
  static const IconData coffee = PhosphorIconsRegular.coffee;
  static const IconData fashion = PhosphorIconsRegular.tShirt;
  static const IconData travel = PhosphorIconsRegular.airplaneTilt;
  static const IconData tech = PhosphorIconsRegular.cpu;
}
