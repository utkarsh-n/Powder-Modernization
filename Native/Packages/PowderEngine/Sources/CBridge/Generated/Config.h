#pragma once
// SwiftPM defines DEBUG as a macro; upstream uses a typed constant.
#ifdef DEBUG
#undef DEBUG
#endif
#include "VcsTag.h"
#include "common/Version.h"

constexpr bool SET_WINDOW_ICON          = false;
constexpr bool DEBUG                    = false;
constexpr bool X86_KILL_DENORMALS       = false;
constexpr bool BETA                     = false;
constexpr bool SNAPSHOT                 = false;
constexpr bool MOD                      = false;
constexpr bool NOHTTP                   = true;
constexpr bool LUACONSOLE               = false;
constexpr bool ALLOW_FAKE_NEWER_VERSION = false;
constexpr bool USE_UPDATESERVER         = false;
constexpr bool CAN_INSTALL              = false;
constexpr bool SHARED_DATA_FOLDER       = false;
constexpr bool USE_BLUESCREEN           = false;
constexpr bool INSTALL_CHECK            = false;
constexpr bool IGNORE_UPDATES           = false;
constexpr bool ENFORCE_HTTPS            = false;
constexpr bool SECURE_CIPHERS_ONLY      = false;
constexpr bool PLATFORM_CLIPBOARD       = false;
constexpr bool USE_SYSTEM_CERT_PROVIDER = false;
constexpr bool FFTW_PLAN_MEASURE        = false;
constexpr bool ALLOW_QUIT               = false;
constexpr bool DEFAULT_TOUCH_UI         = false;
constexpr bool ALLOW_DATA_FOLDER        = false;
constexpr char PATH_SEP_CHAR            = '/';

enum ForceWindowFrameOps
{
	forceWindowFrameOpsNone, // usual behaviour
	forceWindowFrameOpsEmbedded, // e.g. into a webpage; this sweeps a few emscripten limitations under the rug
	forceWindowFrameOpsHandheld, // e.g. the system doesn't support windowed mode; includes odd setups like chromebooks
};
constexpr ForceWindowFrameOps FORCE_WINDOW_FRAME_OPS = forceWindowFrameOpsNone;

constexpr char SERVER[]         = "";
constexpr char STATICSERVER[]   = "";
constexpr char UPDATESERVER[]   = "";
constexpr char IDENT_PLATFORM[] = "APPLE";
constexpr char IDENT[]          = "headless";
constexpr char APPNAME[]        = "Powder Native";
constexpr char APPCOMMENT[]     = "";
constexpr char APPEXE[]         = "";
constexpr char APPID[]          = "org.powder.native";
constexpr char APPDATA[]        = "";
constexpr char APPVENDOR[]      = "The Powder Toy contributors";
constexpr char PACKAGE_MODE[]   = "";

constexpr int MOD_ID               = 0;

struct DisplayVersionWithBuild
{
	Version<2> displayVersion;
	size_t build;
};
constexpr DisplayVersionWithBuild APP_VERSION = { { 100, 1 }, 400 };
constexpr DisplayVersionWithBuild UPSTREAM_VERSION = { { 100, 1 }, 400 };

constexpr auto DISPLAY_VERSION = APP_VERSION.displayVersion;

constexpr char IDENT_RELTYPE    = SNAPSHOT ? 'S' : (BETA ? 'B' : 'R');

constexpr char LOCAL_SAVE_DIR[] = "Saves";
constexpr char STAMPS_DIR[]     = "stamps";
constexpr char BRUSH_DIR[]      = "Brushes";

constexpr int httpMaxConcurrentStreams = 50;
constexpr int httpConnectTimeoutS      = 15;
