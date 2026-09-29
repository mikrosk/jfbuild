// SDL interface layer
// for the Build Engine
// by Jonathon Fowler (jf@jonof.id.au)
//
// Use SDL1.2 from http://www.libsdl.org

#include "build.h"

#include "SDL.h"

#if (SDL_MAJOR_VERSION != 1) || (SDL_MINOR_VERSION != 2)
#  error This must be built with SDL1.2
#endif
#if USE_OPENGL
#  error OpenGL is not supported with SDL1.2
#endif

#include <stdlib.h>
#include <math.h>

#include "baselayer_priv.h"
#include "sdlayer.h"
#include "cache1d.h"
#include "pragmas.h"
#include "a.h"
#include "osd.h"

static char apptitle[256] = "Build Engine";
static char wintitle[256] = "";

// video
static SDL_Surface *sdl_surface;	// The video surface.
static SDL_Surface *sdl_appicon;
static unsigned char *frame;
static float curshadergamma = 1.f, cursysgamma = -1.f;
static int desktopw, desktoph;
static char displayname[128];
int displaycnt = 1;	// SDL1.2 knows only one display.

// input
static char keynames[256][24];
static char keydown[256];	// Physical key state, for detecting auto-repeat.
static char mouseacquired=0,moustat=0;
static SDL_Joystick *joystick = NULL;

struct keytranslate {
	unsigned char normal;
	unsigned char controlchar;  // an ASCII control character to insert into the character fifo
};
#define WITH_CONTROL_KEY 0x80
static struct keytranslate keytranslation[SDLK_LAST];
static int buildkeytranslationtable(void);

static void enumdisplays(void);
static void shutdownvideo(void);

static void loadappicon(void);

int wm_msgbox(const char *name, const char *fmt, ...)
{
	char *buf = NULL;
	int rv;
	va_list va;

	if (!name) {
		name = apptitle;
	}

	va_start(va,fmt);
	rv = Bvasprintf(&buf,fmt,va);
	va_end(va);

	if (rv < 0) return -1;

	puts(buf);

	free(buf);

	return 1;
}

int wm_ynbox(const char *name, const char *fmt, ...)
{
	char *buf = NULL;
	int rv;
	va_list va;

	if (!name) {
		name = apptitle;
	}

	va_start(va,fmt);
	rv = Bvasprintf(&buf,fmt,va);
	va_end(va);

	if (rv < 0) return -1;

	puts(buf);
	puts("   (assuming 'No')");

	free(buf);

	return 0;
}

int wm_filechooser(const char *initialdir, const char *initialfile, const char *type, int foropen, char **choice)
{
	(void)initialdir; (void)initialfile; (void)type; (void)foropen; (void)choice;
	return -1;
}

int wm_idle(void *ptr)
{
	(void)ptr;
	return 0;
}

void wm_setapptitle(const char *name)
{
	if (name) {
		Bstrncpy(apptitle, name, sizeof(apptitle)-1);
		apptitle[ sizeof(apptitle)-1 ] = 0;
	}
}

void wm_setwindowtitle(const char *name)
{
	if (name) {
		Bstrncpy(wintitle, name, sizeof(wintitle)-1);
		wintitle[ sizeof(wintitle)-1 ] = 0;
	}

	if (SDL_WasInit(SDL_INIT_VIDEO)) {
		SDL_WM_SetCaption(wintitle, NULL);
	}
}

void wm_allowbackgroundidle(int onf)
{
	(void)onf;
}

void wm_allowtaskswitching(int onf)
{
	(void)onf;
}



//
//
// ---------------------------------------
//
// System
//
// ---------------------------------------
//
//

int main(int argc, char *argv[])
{
	int r;

	buildkeytranslationtable();

	if (SDL_Init(SDL_INIT_VIDEO)) {
		buildprintf("Early initialisation of SDL failed! (%s)\n", SDL_GetError());
		return 1;
	}
	atexit(SDL_Quit);

	_buildargc = argc;
	_buildargv = (const char **)argv;

	startwin_open();
	baselayer_init();

	loadappicon();

	r = app_main(_buildargc, (char const * const*)_buildargv);

	if (sdl_appicon) SDL_FreeSurface(sdl_appicon);

	startwin_close();

	return r;
}


//
// initsystem() -- init SDL systems
//
int initsystem(void)
{
	const SDL_version *linked = SDL_Linked_Version();
	SDL_version compiled;
	char drvname[64];

	SDL_VERSION(&compiled);

	buildprintf("SDL1.2 system interface "
		  "(compiled with SDL version %d.%d.%d, runtime version %d.%d.%d)\n",
		compiled.major, compiled.minor, compiled.patch,
		linked->major, linked->minor, linked->patch);

	if (SDL_VideoDriverName(drvname, sizeof(drvname)))
		buildprintf("Using \"%s\" video driver\n", drvname);

	enumdisplays();

	atexit(uninitsystem);

	return 0;
}


//
// uninitsystem() -- uninit SDL systems
//
void uninitsystem(void)
{
	uninitinput();
	uninitmouse();
	uninittimer();

	shutdownvideo();
}


//
// initputs() -- prints a string to the intitialization window
//
void initputs(const char *str)
{
	startwin_puts(str);
	startwin_idle(NULL);
	wm_idle(NULL);
}


//
// debugprintf() -- prints a debug string to stderr
//
void debugprintf(const char *f, ...)
{
#ifdef DEBUGGINGAIDS
	va_list va;

	va_start(va,f);
	Bvfprintf(stderr, f, va);
	va_end(va);
#endif
	(void)f;
}


//
//
// ---------------------------------------
//
// All things Input
//
// ---------------------------------------
//
//

//
// initinput() -- init input system
//
int initinput(void)
{
	int i;

	inputdevices = 1|2; // keyboard (1) and mouse (2)
	mouseacquired = 0;

	memset(keynames,0,sizeof(keynames));
	memset(keydown,0,sizeof(keydown));
	for (i=0; i<SDLK_LAST; i++) {
		if (!keytranslation[i].normal) continue;
		strncpy(keynames[ keytranslation[i].normal ], SDL_GetKeyName((SDLKey)i), sizeof(keynames[0])-1);
	}

	if (SDL_InitSubSystem(SDL_INIT_JOYSTICK) == 0) {
		// Enumerate joysticks.
		if (SDL_NumJoysticks() < 1) {
			buildputs("No joysticks found\n");
		} else {
			int numjoysticks = SDL_NumJoysticks();
			buildputs("Joysticks:\n");
			for (i = 0; i < numjoysticks; i++) {
				buildprintf("  - %s\n", SDL_JoystickName(i));
				if (!joystick) {
					joystick = SDL_JoystickOpen(i);
				}
			}
			if (joystick) {
				buildprintf("Using joystick %s\n", SDL_JoystickName(SDL_JoystickIndex(joystick)));

				inputdevices |= 4;
				joynumaxes    = min((int)Barraylen(joyaxis), SDL_JoystickNumAxes(joystick));
				joynumbuttons = min(32, SDL_JoystickNumButtons(joystick));
				SDL_JoystickEventState(SDL_ENABLE);
			} else {
				buildprintf("No joysticks are usable\n");
			}
		}
	}

	return 0;
}

//
// uninitinput() -- uninit input system
//
void uninitinput(void)
{
	uninitmouse();

	if (joystick) {
		SDL_JoystickClose(joystick);
		joystick = NULL;
	}
}

const char *getkeyname(int num)
{
	if ((unsigned)num >= 256) return NULL;
	return keynames[num];
}

const char *getjoyname(int what, int num)
{
	static char tmp[64];

	switch (what) {
		case 0: // axis
			if ((unsigned)num >= (unsigned)joynumaxes) return NULL;
			Bsprintf(tmp, "Axis %d", num+1);
			return tmp;
		case 1: // button
			if ((unsigned)num >= (unsigned)joynumbuttons) return NULL;
			Bsprintf(tmp, "Button %d", num+1);
			return tmp;
		default:
			return NULL;
	}
}


//
// initmouse() -- init mouse input
//
int initmouse(void)
{
	moustat=1;
	grabmouse(1);
	return 0;
}

//
// uninitmouse() -- uninit mouse input
//
void uninitmouse(void)
{
	grabmouse(0);
	moustat=0;
}


//
// setrelativemouse() -- SDL1.2 reports relative motion while input is grabbed and the cursor hidden
//
static void setrelativemouse(int a)
{
	if (!SDL_GetVideoSurface()) return;
	SDL_WM_GrabInput(a ? SDL_GRAB_ON : SDL_GRAB_OFF);
	SDL_ShowCursor(a ? SDL_DISABLE : SDL_ENABLE);
}

//
// grabmouse() -- show/hide mouse cursor
//
void grabmouse(int a)
{
	if (appactive && moustat) {
		if (a != mouseacquired) {
			setrelativemouse(a);
			mouseacquired = a;
		}
	} else {
		mouseacquired = a;
	}
	mousex = mousey = 0;
}


//
// readmousexy() -- return mouse motion information
//
void readmousexy(int *x, int *y)
{
	if (!mouseacquired || !appactive || !moustat) { *x = *y = 0; return; }
	*x = mousex;
	*y = mousey;
	mousex = mousey = 0;
}

//
// readmousebstatus() -- return mouse button information
//
void readmousebstatus(int *b)
{
	if (!mouseacquired || !appactive || !moustat) *b = 0;
	else *b = mouseb;
	// clear mousewheel events - the game has them now (in *b)
	// the other mousebuttons are cleared when there's a "button released"
	// event, but for the mousewheel that doesn't work, as it's released immediately
	mouseb &= ~(1<<4 | 1<<5);
}

//
// releaseallbuttons()
//
void releaseallbuttons(void)
{
}


//
//
// ---------------------------------------
//
// All things Timer
// Ken did this
//
// ---------------------------------------
//
//

static Uint32 timerfreq=0;
static Uint32 timerlastsample=0;
static Uint32 timerticspersec=0;
static void (*usertimercallback)(void) = NULL;

//
// inittimer() -- initialise timer
//
int inittimer(int tickspersecond, void(*callback)(void))
{
	if (timerfreq) return 0;    // already installed

	buildputs("Initialising timer\n");

	timerfreq = 1000;	// SDL_GetTicks() counts milliseconds
	timerticspersec = tickspersecond;
	timerlastsample = (Uint32)((Uint64)SDL_GetTicks() * timerticspersec / timerfreq);

	usertimercallback = callback;

	return 0;
}

//
// uninittimer() -- shut down timer
//
void uninittimer(void)
{
	if (!timerfreq) return;

	timerfreq=0;
}

//
// sampletimer() -- update totalclock
//
void sampletimer(void)
{
	int n;

	if (!timerfreq) return;

	n = (int)((Uint64)SDL_GetTicks() * timerticspersec / timerfreq) - timerlastsample;
	if (n>0) {
		totalclock += n;
		timerlastsample += n;
	}

	if (usertimercallback) for (; n>0; n--) usertimercallback();
}

//
// getticks() -- returns a millisecond ticks count
//
unsigned int getticks(void)
{
	return (unsigned int)SDL_GetTicks();
}

//
// getusecticks() -- returns a microsecond ticks count
//
unsigned int getusecticks(void)
{
	return (unsigned int)SDL_GetTicks() * 1000;
}


//
// gettimerfreq() -- returns the number of ticks per second the timer is configured to generate
//
int gettimerfreq(void)
{
	return timerticspersec;
}



//
//
// ---------------------------------------
//
// All things Video
//
// ---------------------------------------
//
//

static void enumdisplays(void)
{
	const SDL_VideoInfo *vinfo;

	// The desktop size is known before the first mode set.
	vinfo = SDL_GetVideoInfo();
	if (vinfo && vinfo->current_w > 0 && vinfo->current_h > 0) {
		desktopw = vinfo->current_w;
		desktoph = vinfo->current_h;
	} else {
		desktopw = 320;
		desktoph = 240;
	}

	Bstrcpy(displayname, "Primary display");

	debugprintf("Displays available:\n");
	debugprintf("  %d) %s (%dx%d)\n", 0, displayname, desktopw, desktoph);
}

//
// getvalidmodes() -- figure out what video modes are available
//
void getvalidmodes(void)
{
	SDL_PixelFormat pf;
	SDL_Rect **modes;
	int i;

	if (validmodecnt) return;

	// Fullscreen modes
	memset(&pf, 0, sizeof(pf));
	pf.BitsPerPixel = 8;
	pf.BytesPerPixel = 1;
	modes = SDL_ListModes(&pf, SDL_FULLSCREEN | SDL_HWPALETTE);
	if (modes == (SDL_Rect **)-1) {
		addstandardvalidmodes(desktopw, desktoph, 8, 1, 0, 0, -1);
	} else if (modes) {
		for (i=0; modes[i]; i++) {
			addvalidmode(modes[i]->w, modes[i]->h, 8, 1, 0, 0, -1);
		}
	}

	// Windowed modes
	addstandardvalidmodes(desktopw, desktoph, 8, 0, 0, 0, -1);

	sortvalidmodes();
}

static void shutdownvideo(void)
{
	if (frame) {
		free(frame);
		frame = NULL;
	}

	// The video surface is owned by SDL and freed on the next mode set or at SDL_Quit().
	sdl_surface = NULL;
}

//
// setvideomode() -- set SDL video mode
//
int setvideomode(int xdim, int ydim, int bitspp, int fullsc)
{
	int regrab = 0;
	int flags, display, modenum;
	const char *str;

	if ((fullsc == fullscreen) && (xdim == xres) && (ydim == yres) && (bitspp == bpp) && !videomodereset) {
		OSD_ResizeDisplay(xres,yres);
		return 0;
	}

	if (bitspp != 8) return -1;

	display = fullsc>>8;
	if (display >= displaycnt) display = 0, fullsc &= 255; // Display number out of range, use primary instead.
	modenum = checkvideomode(&xdim,&ydim,bitspp,fullsc,0);
	if (modenum < 0) return -1;
	else if (modenum == VIDEOMODE_RELAXED && (fullsc&255)) return -1; // Must be a perfect match for fullscreen.

	if (mouseacquired) {
		regrab = 1;
		grabmouse(0);
	}

	if (baselayer_videomodewillchange) baselayer_videomodewillchange();
	shutdownvideo();

	if (fullsc&255) str = "Setting video mode %dx%d (%d-bit fullscreen, display %d)\n";
	else str = "Setting video mode %dx%d (%d-bit windowed)\n";
	buildprintf(str,xdim,ydim,bitspp,display);

	// The icon and title must be set before the video mode.
	if (sdl_appicon) SDL_WM_SetIcon(sdl_appicon, NULL);
	SDL_WM_SetCaption(wintitle, NULL);

	flags = SDL_SWSURFACE | SDL_HWPALETTE;
	if (fullsc&255) flags |= SDL_FULLSCREEN;

	// SDL emulates an 8-bit surface if the display cannot provide one.
	sdl_surface = SDL_SetVideoMode(xdim, ydim, 8, flags);
	if (!sdl_surface) {
		buildprintf("Error setting video mode: %s\n", SDL_GetError());
		return -1;
	}

	{
		int i, j, pitch;

		// Round up to a multiple of 4.
		pitch = (((xdim|1) + 4) & ~3);

		frame = (unsigned char *) malloc(pitch * ydim);
		if (!frame) {
			buildputs("Unable to allocate framebuffer\n");
			return -1;
		}

		frameplace = (intptr_t) frame;
		bytesperline = pitch;
		imageSize = bytesperline * ydim;
		numpages = 1;

		setvlinebpl(bytesperline);
		for (i = j = 0; i <= ydim; i++) {
			ylookup[i] = j;
			j += bytesperline;
		}
	}

	xres = xdim;
	yres = ydim;
	bpp = bitspp;
	fullscreen = fullsc;

	videomodereset = 0;
	if (baselayer_videomodedidchange) baselayer_videomodedidchange();
	OSD_ResizeDisplay(xres,yres);

	// setpalettefade will set the palette according to whether gamma worked
	setpalettefade(palfadergb.r, palfadergb.g, palfadergb.b, palfadedelta);

	if (regrab) grabmouse(1);

	startwin_close();

	// Start listening for character input.
	SDL_EnableUNICODE(1);
	SDL_EnableKeyRepeat(SDL_DEFAULT_REPEAT_DELAY, SDL_DEFAULT_REPEAT_INTERVAL);

	return 0;
}


//
// getdisplaynamee() -- returns a human friendly name for a particular display
//
const char *getdisplayname(int display)
{
	if ((unsigned)display >= (unsigned)displaycnt) return NULL;
	return displayname;
}


//
// showframe() -- update the display
//
void showframe(void)
{
	unsigned char *pixels, *in;
	int y;

	if (!sdl_surface) return;

	if (SDL_MUSTLOCK(sdl_surface) && SDL_LockSurface(sdl_surface)) {
		debugprintf("Could not lock surface: %s\n", SDL_GetError());
		return;
	}

	pixels = (unsigned char *)sdl_surface->pixels;
	in = frame;
	for (y = yres - 1; y >= 0; y--) {
		memcpy(pixels, in, xres);
		pixels += sdl_surface->pitch;
		in += bytesperline;
	}

	if (SDL_MUSTLOCK(sdl_surface)) SDL_UnlockSurface(sdl_surface);

	SDL_Flip(sdl_surface);
}


//
// setpalette() -- set palette values
//
int setpalette(int start, int num, unsigned char *dapal)
{
	SDL_Color colors[256];
	int i;

	(void)start; (void)num; (void)dapal;

	if (!sdl_surface) return 0;

	for (i = 0; i < 256; i++) {
		colors[i].r = curpalettefaded[i].r;
		colors[i].g = curpalettefaded[i].g;
		colors[i].b = curpalettefaded[i].b;
		colors[i].unused = 0;
	}
	SDL_SetPalette(sdl_surface, SDL_LOGPAL | SDL_PHYSPAL, colors, 0, 256);

	return 0;
}


//
// setsysgamma
//
int setsysgamma(float shadergamma, float sysgamma)
{
	int r = 0;
	if (sdl_surface) {
		if (sysgamma < 0.f) r = SDL_SetGamma(1.0, 1.0, 1.0);
		else r = SDL_SetGamma(sysgamma, sysgamma, sysgamma);
	}
	if (r == 0) { curshadergamma = shadergamma; cursysgamma = sysgamma; }
	return r;
}


static void loadappicon(void)
{
	extern const unsigned char appicon_bmp[];
	extern const int appicon_bmp_size;
	SDL_RWops *rwops;

	rwops = SDL_RWFromConstMem(appicon_bmp, appicon_bmp_size);
	if (!rwops) {
		debugprintf("loadappicon: error creating rwops object: %s\n", SDL_GetError());
		return;
	}

	sdl_appicon = SDL_LoadBMP_RW(rwops, 1);
	if (!sdl_appicon) {
		debugprintf("loadappicon: error creating appicon surface: %s\n", SDL_GetError());
	}
}

//
//
// ---------------------------------------
//
// Miscellany
//
// ---------------------------------------
//
//


//
// handleevents() -- process the SDL message queue
//   returns !0 if there was an important event worth checking (like quitting)
//
int handleevents(void)
{
	int code, rv=0, j, control;
	SDL_Event ev;
	static int firstcall = 1;

	while (SDL_PollEvent(&ev)) {
		switch (ev.type) {
			case SDL_KEYUP:
				// (un)grab mouse with ctrl-g
				if (ev.key.keysym.sym == SDLK_g
					&& (ev.key.keysym.mod & KMOD_CTRL)) {
					grabmouse(!mouseacquired);
					break;
				}
				// else, fallthrough
			case SDL_KEYDOWN:
				code = keytranslation[ev.key.keysym.sym].normal;
				control = keytranslation[ev.key.keysym.sym].controlchar;

				if (control && ev.key.type == SDL_KEYDOWN) {
					int needcontrol = (control & WITH_CONTROL_KEY) == WITH_CONTROL_KEY;
					int mod = ev.key.keysym.mod & ~(KMOD_CAPS|KMOD_NUM);
					control &= ~WITH_CONTROL_KEY;

					// May need to insert a control character into the ascii input
					// FIFO depending on what the state of the control keys are.
					if ((needcontrol  && mod && (mod & KMOD_CTRL) == mod) ||
						(!needcontrol && (mod == KMOD_NONE))) {
						if (OSD_HandleChar(control)) {
							if (((keyasciififoend+1)&(KEYFIFOSIZ-1)) != keyasciififoplc) {
								keyasciififo[keyasciififoend] = control;
								keyasciififoend = ((keyasciififoend+1)&(KEYFIFOSIZ-1));
							}
						}
					}
				}

				// hook in the osd
				if (code == OSD_CaptureKey(-1)) {
					// The character produced by the OSD toggle key is ignored.
					if (ev.key.type == SDL_KEYDOWN) {
						OSD_ShowDisplay(-1);
					}
					break;
				}

				// Printable characters; control characters were handled above.
				if (ev.key.type == SDL_KEYDOWN) {
					int ch = ev.key.keysym.unicode;
					if (ch >= 0x20 && ch < 0x7f && OSD_HandleChar(ch)) {
						if (((keyasciififoend+1)&(KEYFIFOSIZ-1)) != keyasciififoplc) {
							keyasciififo[keyasciififoend] = ch;
							keyasciififoend = ((keyasciififoend+1)&(KEYFIFOSIZ-1));
						}
					}
				}

				if (OSD_HandleKey(code, (ev.key.type == SDL_KEYDOWN)) == 0)
					break;

				if (ev.key.type == SDL_KEYDOWN) {
					// SDL1.2 does not flag auto-repeated key presses.
					if (!keystatus[code] && !keydown[code]) keystatus[code] = 1;
					keydown[code] = 1;
					keyfifo[keyfifoend] = code;
					keyfifo[(keyfifoend+1)&(KEYFIFOSIZ-1)] = 1;
					keyfifoend = ((keyfifoend+2)&(KEYFIFOSIZ-1));
				} else {
					keystatus[code] = 0;
					keydown[code] = 0;
					keyfifo[keyfifoend] = code;
					keyfifo[(keyfifoend+1)&(KEYFIFOSIZ-1)] = 0;
					keyfifoend = ((keyfifoend+2)&(KEYFIFOSIZ-1));
				}
				break;

			case SDL_ACTIVEEVENT:
				if (ev.active.state & SDL_APPINPUTFOCUS) {
					appactive = ev.active.gain;
					if (mouseacquired && moustat) {
						setrelativemouse(appactive);
					}
					rv=-1;
				}
				break;

			case SDL_MOUSEBUTTONDOWN:
			case SDL_MOUSEBUTTONUP:
				switch (ev.button.button) {
					case SDL_BUTTON_LEFT: j = 0; break;
					case SDL_BUTTON_RIGHT: j = 1; break;
					case SDL_BUTTON_MIDDLE: j = 2; break;
					case SDL_BUTTON_WHEELDOWN: j = 4; break;
					case SDL_BUTTON_WHEELUP: j = 5; break;
					default: j = -1; break;
				}
				if (j<0) break;

				if (ev.button.state == SDL_PRESSED)
					mouseb |= (1<<j);
				else if (j < 4) // mousewheel 'release' is done in readmousebstatus()
					mouseb &= ~(1<<j);
				break;

			case SDL_MOUSEMOTION:
				if (!firstcall) {
					if (appactive) {
						mousex += ev.motion.xrel;
						mousey += ev.motion.yrel;
					}
				}
				break;

			case SDL_JOYAXISMOTION:
				if (appactive && ev.jaxis.axis < joynumaxes) {
					joyaxis[ ev.jaxis.axis ] = ev.jaxis.value;
				}
				break;

			case SDL_JOYBUTTONDOWN:
			case SDL_JOYBUTTONUP:
				if (appactive && ev.jbutton.button < joynumbuttons) {
					if (ev.jbutton.state == SDL_PRESSED)
						joyb |= 1 << ev.jbutton.button;
					else
						joyb &= ~(1 << ev.jbutton.button);
				}
				break;

			case SDL_QUIT:
				quitevent = 1;
				rv=-1;
				break;

			default:
				//buildprintf("Got event (%d)\n", ev.type);
				break;
		}
	}

	sampletimer();
	startwin_idle(NULL);
	wm_idle(NULL);

	firstcall = 0;

	return rv;
}


static int buildkeytranslationtable(void)
{
	memset(keytranslation,0,sizeof(keytranslation));

#define MAP(x,y) keytranslation[x].normal = y
#define MAPC(x,y,c) keytranslation[x].normal = y, keytranslation[x].controlchar = c

	MAPC(SDLK_BACKSPACE, 0xe, 0x8);
	MAPC(SDLK_TAB,       0xf, 0x9);
	MAPC(SDLK_RETURN,    0x1c, 0xd);
	MAP(SDLK_PAUSE,     0x59);  // 0x1d + 0x45 + 0x9d + 0xc5
	MAPC(SDLK_ESCAPE,    0x1, 0x1b);
	MAP(SDLK_SPACE,     0x39);
	MAP(SDLK_QUOTE,     0x28);
	MAP(SDLK_COMMA,     0x33);
	MAP(SDLK_MINUS,     0xc);
	MAP(SDLK_PERIOD,    0x34);
	MAP(SDLK_SLASH,     0x35);
	MAP(SDLK_0,     0xb);
	MAP(SDLK_1,     0x2);
	MAP(SDLK_2,     0x3);
	MAP(SDLK_3,     0x4);
	MAP(SDLK_4,     0x5);
	MAP(SDLK_5,     0x6);
	MAP(SDLK_6,     0x7);
	MAP(SDLK_7,     0x8);
	MAP(SDLK_8,     0x9);
	MAP(SDLK_9,     0xa);
	MAP(SDLK_SEMICOLON, 0x27);
	MAP(SDLK_EQUALS,    0xd);
	// Unshifted symbols of non-US layouts, mapped to the US key producing them when shifted.
	MAP(SDLK_EXCLAIM,   0x2);   // '1'
	MAP(SDLK_QUOTEDBL,  0x28);  // '''
	MAP(SDLK_HASH,      0x4);   // '3'
	MAP(SDLK_DOLLAR,    0x5);   // '4'
	MAP(37,             0x6);   // '5', SDL1.2 has no keysym for '%'
	MAP(SDLK_AMPERSAND, 0x8);   // '7'
	MAP(SDLK_ASTERISK,  0x9);   // '8'
	MAP(SDLK_LEFTPAREN, 0xa);   // '9'
	MAP(SDLK_RIGHTPAREN, 0xb);  // '0'
	MAP(SDLK_PLUS,      0xd);   // '='
	MAP(SDLK_COLON,     0x27);  // ';'
	MAP(SDLK_LESS,      0x33);  // ','
	MAP(SDLK_GREATER,   0x34);  // '.'
	MAP(SDLK_QUESTION,  0x35);  // '/'
	MAP(SDLK_AT,        0x3);   // '2'
	MAP(SDLK_CARET,     0x7);   // '6'
	MAP(SDLK_UNDERSCORE, 0xc);  // '-'
	MAPC(SDLK_LEFTBRACKET,   0x1a, 0x1b | WITH_CONTROL_KEY);
	MAPC(SDLK_BACKSLASH, 0x2b, 0x1c | WITH_CONTROL_KEY);
	MAPC(SDLK_RIGHTBRACKET,  0x1b, 0x1d | WITH_CONTROL_KEY);
	MAP(SDLK_BACKQUOTE, 0x29);
	MAPC(SDLK_a,     0x1e, 0x1 | WITH_CONTROL_KEY);
	MAPC(SDLK_b,     0x30, 0x2 | WITH_CONTROL_KEY);
	MAPC(SDLK_c,     0x2e, 0x3 | WITH_CONTROL_KEY);
	MAPC(SDLK_d,     0x20, 0x4 | WITH_CONTROL_KEY);
	MAPC(SDLK_e,     0x12, 0x5 | WITH_CONTROL_KEY);
	MAPC(SDLK_f,     0x21, 0x6 | WITH_CONTROL_KEY);
	MAPC(SDLK_g,     0x22, 0x7 | WITH_CONTROL_KEY);
	MAPC(SDLK_h,     0x23, 0x8 | WITH_CONTROL_KEY);
	MAPC(SDLK_i,     0x17, 0x9 | WITH_CONTROL_KEY);
	MAPC(SDLK_j,     0x24, 0xa | WITH_CONTROL_KEY);
	MAPC(SDLK_k,     0x25, 0xb | WITH_CONTROL_KEY);
	MAPC(SDLK_l,     0x26, 0xc | WITH_CONTROL_KEY);
	MAPC(SDLK_m,     0x32, 0xd | WITH_CONTROL_KEY);
	MAPC(SDLK_n,     0x31, 0xe | WITH_CONTROL_KEY);
	MAPC(SDLK_o,     0x18, 0xf | WITH_CONTROL_KEY);
	MAPC(SDLK_p,     0x19, 0x10 | WITH_CONTROL_KEY);
	MAPC(SDLK_q,     0x10, 0x11 | WITH_CONTROL_KEY);
	MAPC(SDLK_r,     0x13, 0x12 | WITH_CONTROL_KEY);
	MAPC(SDLK_s,     0x1f, 0x13 | WITH_CONTROL_KEY);
	MAPC(SDLK_t,     0x14, 0x14 | WITH_CONTROL_KEY);
	MAPC(SDLK_u,     0x16, 0x15 | WITH_CONTROL_KEY);
	MAPC(SDLK_v,     0x2f, 0x16 | WITH_CONTROL_KEY);
	MAPC(SDLK_w,     0x11, 0x17 | WITH_CONTROL_KEY);
	MAPC(SDLK_x,     0x2d, 0x18 | WITH_CONTROL_KEY);
	MAPC(SDLK_y,     0x15, 0x19 | WITH_CONTROL_KEY);
	MAPC(SDLK_z,     0x2c, 0x1a | WITH_CONTROL_KEY);
	MAP(SDLK_DELETE,    0xd3);
	MAP(SDLK_KP0,       0x52);
	MAP(SDLK_KP1,       0x4f);
	MAP(SDLK_KP2,       0x50);
	MAP(SDLK_KP3,       0x51);
	MAP(SDLK_KP4,       0x4b);
	MAP(SDLK_KP5,       0x4c);
	MAP(SDLK_KP6,       0x4d);
	MAP(SDLK_KP7,       0x47);
	MAP(SDLK_KP8,       0x48);
	MAP(SDLK_KP9,       0x49);
	MAP(SDLK_KP_PERIOD, 0x53);
	MAP(SDLK_KP_DIVIDE, 0xb5);
	MAP(SDLK_KP_MULTIPLY,   0x37);
	MAP(SDLK_KP_MINUS,  0x4a);
	MAP(SDLK_KP_PLUS,   0x4e);
	MAPC(SDLK_KP_ENTER,  0x9c, 0xd);
	MAP(SDLK_UP,        0xc8);
	MAP(SDLK_DOWN,      0xd0);
	MAP(SDLK_RIGHT,     0xcd);
	MAP(SDLK_LEFT,      0xcb);
	MAP(SDLK_INSERT,    0xd2);
	MAP(SDLK_HOME,      0xc7);
	MAP(SDLK_END,       0xcf);
	MAP(SDLK_PAGEUP,    0xc9);
	MAP(SDLK_PAGEDOWN,  0xd1);
	MAP(SDLK_F1,        0x3b);
	MAP(SDLK_F2,        0x3c);
	MAP(SDLK_F3,        0x3d);
	MAP(SDLK_F4,        0x3e);
	MAP(SDLK_F5,        0x3f);
	MAP(SDLK_F6,        0x40);
	MAP(SDLK_F7,        0x41);
	MAP(SDLK_F8,        0x42);
	MAP(SDLK_F9,        0x43);
	MAP(SDLK_F10,       0x44);
	MAP(SDLK_F11,       0x57);
	MAP(SDLK_F12,       0x58);
	MAP(SDLK_NUMLOCK,   0x45);
	MAP(SDLK_CAPSLOCK,  0x3a);
	MAP(SDLK_SCROLLOCK, 0x46);
	MAP(SDLK_RSHIFT,    0x36);
	MAP(SDLK_LSHIFT,    0x2a);
	MAP(SDLK_RCTRL,     0x9d);
	MAP(SDLK_LCTRL,     0x1d);
	MAP(SDLK_RALT,      0xb8);
	MAP(SDLK_LALT,      0x38);
	MAP(SDLK_LSUPER,    0xdb);  // win l
	MAP(SDLK_RSUPER,    0xdc);  // win r
	MAP(SDLK_PRINT,     -2);    // 0xaa + 0xb7
	MAP(SDLK_SYSREQ,    0x54);  // alt+printscr
	MAP(SDLK_BREAK,     0xb7);  // ctrl+pause
	MAP(SDLK_MENU,      0xdd);  // win menu?

	return 0;
}
