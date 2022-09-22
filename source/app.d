import std.stdio;
import etc.linux.memoryerror;
import bindbc.sdl;
import std.string;
import std.typecons : Tuple, tuple;
import std.math.traits;

/// Exception for SDL related issues
class SDLException : Exception
{
	/// Creates an exception from SDL_GetError()
	this(string file = __FILE__, size_t line = __LINE__) nothrow @nogc
	{
		super(cast(string) SDL_GetError().fromStringz, file, line);
	}
}

class Chunk
{
	ubyte[CHUNKSIZE][CHUNKSIZE] data;
	ubyte[CHUNKSIZE][CHUNKSIZE] newdata;
	bool processed;
	ubyte emptyIterations;

	this()
	{

	}

	void iterate()
	{
		foreach (int x; 0 .. CHUNKSIZE)
		{
			foreach (int y; 0 .. CHUNKSIZE)
			{
				//dfmt off
				newdata[x][y] = cast(ubyte) (
					getNeighbours(x - 1, y - 1) + getNeighbours(x    , y - 1) + getNeighbours(x + 1, y - 1) +
					getNeighbours(x - 1, y    ) +                         getNeighbours(x + 1, y    ) +
					getNeighbours(x - 1, y + 1) + getNeighbours(x    , y + 1) + getNeighbours(x + 1, y + 1)) ;

				//dfmt on
			}
		}

		foreach (x; 0 .. CHUNKSIZE)
		{
			foreach (y; 0 .. CHUNKSIZE)
			{
				ubyte* count = &newdata[x][y];
				ubyte* current = &data[x][y];
				//dfmt off
				if(*count < 2 || *count > 3)
					*current = 0;
				else if(*count == 3)
					*current = 1;
			}
		}
		
	}
}

immutable int CHUNKSIZE = 32;

SDL_Renderer* sdlr;
bool running;
int windowW;
int windowH;
int mouseX;
int mouseY;
bool mouseL;
bool mouseM;
bool mouseR;
Uint8* keystates;
Uint16 keymods;
ubyte cSize = 8;

Chunk[Tuple!(int, int)] field;

void main()
{
	registerMemoryErrorHandler();

	writeln(sdlSupport);

	if (loadSDL() != sdlSupport)
		writeln("Error loading SDL library");

	if (SDL_Init(SDL_INIT_VIDEO) < 0)
		throw new SDLException();

	scope (exit)
		SDL_Quit();

	windowW = 800;
	windowH = 600;
	auto window = SDL_CreateWindow("SDL Application", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
		windowW, windowH, SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE);
	if (!window)
		throw new SDLException();

	sdlr = SDL_CreateRenderer(window, -1, 0  | SDL_RENDERER_PRESENTVSYNC );

	SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "1");

	init();

	running = true;
	while (running)
	{
		pollEvents();
		tick();
		draw();
		pollEvents();
		draw();
		pollEvents();
		draw();
		pollEvents();
		draw();
		pollEvents();
		draw();
		
	}
}

void init()
{
	field[tuple(0, 0)] = new Chunk();
	Chunk ch = field[tuple(0, 0)];
	ch.data[12][4] = 1;
	ch.data[12][5] = 1;
	ch.data[11][6] = 1;
	ch.data[13][6] = 1;
	ch.data[12][7] = 1;
	ch.data[12][8] = 1;
	ch.data[12][9] = 1;
	ch.data[12][10] = 1;
	ch.data[11][11] = 1;
	ch.data[13][11] = 1;
	ch.data[12][12] = 1;
	ch.data[12][13] = 1;

}

T sign(T)(T val)
{
	return val >> (T.sizeof * 8 - 1);
}

ubyte getNeighbours(int x, int y)
{
	Chunk* chunk = tuple(x / CHUNKSIZE - x.sign, y / CHUNKSIZE - y.sign) in field;
	return chunk is null ? 0 : chunk.data[x % CHUNKSIZE][y % CHUNKSIZE];
}

ubyte getNeighboursN(int x, int y)
{
	Chunk* chunk = tuple(x / CHUNKSIZE - x.sign, y / CHUNKSIZE - y.sign) in field;
	return chunk is null ? 0 : chunk.newdata[x % CHUNKSIZE][y % CHUNKSIZE];
}

void tick()
{
	if(mouseL)
	{
		auto tup = screen2cell(mouseX, mouseY);
		ubyte* cell = getCell(tup[0], tup[1]);
		if(cell !is null)
				*cell = 1;
	}

	foreach(chunk; field) {
		chunk.iterate();
	}
}

void draw()
{
	sdlr.SDL_SetRenderDrawColor(0, 0, 0, 255);
	sdlr.SDL_RenderClear();

	foreach(i, chunk; field) {
		foreach (x; 0 .. CHUNKSIZE)
		{
			foreach (y; 0 .. CHUNKSIZE)
			{
				if(chunk.data[x][y])
				{
					sdlr.SDL_SetRenderDrawColor(255, 255, 255, 255);
					sdlr.SDL_RenderFillRect(new SDL_Rect(x * cSize, y * cSize, cSize, cSize));
				}
			}
		}
		sdlr.SDL_SetRenderDrawColor(0, 255, 0, 128);
		sdlr.SDL_RenderDrawRect(new SDL_Rect(i[0] * CHUNKSIZE * cSize, i[1] * CHUNKSIZE * cSize, CHUNKSIZE * cSize, CHUNKSIZE * cSize));
	}

	sdlr.SDL_RenderPresent();
}

void pollEvents()
{
	SDL_Event event;
	while (SDL_PollEvent(&event))
	{
		switch (event.type)
		{
		case SDL_QUIT:
			quit();
			break;
		case SDL_KEYDOWN:
			onKeyDown(event.key);
			break;
		case SDL_KEYUP:
			onKeyUp(event.key);
			break;
		case SDL_TEXTINPUT:
			onTextInput(event.text);
			break;
		case SDL_MOUSEBUTTONDOWN:
			onMouseDown(event.button);
			break;
		case SDL_MOUSEBUTTONUP:
			onMouseUp(event.button);
			break;
		case SDL_MOUSEMOTION:
			onMouseMotion(event.motion);
			break;
		case SDL_MOUSEWHEEL:
			onMouseWheel(event.wheel);
			break;
		case SDL_WINDOWEVENT:
			onWindowEvent(event.window);
			break;
		default:
			// writeln("Unhandled event: ", cast(SDL_EventType) event.type);
		}
	}
}

void quit()
{
	running = false;
}

void onKeyDown(SDL_KeyboardEvent e)
{
	keystates = SDL_GetKeyboardState(null);
	keymods = e.keysym.mod;
	switch (e.keysym.sym)
	{
	case SDLK_ESCAPE:
		quit();
		break;
	default:
	}
}

void onKeyUp(SDL_KeyboardEvent e)
{
	keystates = SDL_GetKeyboardState(null);
	keymods = e.keysym.mod;
	switch (e.keysym.sym)
	{
	default:
	}
}

Tuple!(int,int) screen2cell(int x, int y)
{
	return tuple(x / cSize, y / cSize);
}

ubyte* getCell(int x, int y)
{
	Chunk* chunk = tuple(x / CHUNKSIZE - x.sign, y / CHUNKSIZE - y.sign) in field;
	return chunk is null ? null : &chunk.data[x % CHUNKSIZE][y % CHUNKSIZE];
}

void onMouseDown(SDL_MouseButtonEvent e)
{
	mouseX = e.x;
	mouseY = e.y;
	switch (e.button)
	{
	case SDL_BUTTON_LEFT:
		mouseL = true;
		break;
	case SDL_BUTTON_MIDDLE:
		mouseM = true;
		break;
	case SDL_BUTTON_RIGHT:
		mouseR = true;
		break;
	case SDL_BUTTON_X1:
	case SDL_BUTTON_X2:
	default:
	}
}

void onTextInput(SDL_TextInputEvent e)
{

}

void onMouseUp(SDL_MouseButtonEvent e)
{
	mouseX = e.x;
	mouseY = e.y;
	switch (e.button)
	{
	case SDL_BUTTON_LEFT:
		mouseL = false;
		break;
	case SDL_BUTTON_MIDDLE:
		mouseM = false;
		break;
	case SDL_BUTTON_RIGHT:
		mouseR = false;
		break;
	case SDL_BUTTON_X1:
	case SDL_BUTTON_X2:
	default:
	}
}

void onMouseMotion(SDL_MouseMotionEvent e)
{
	mouseX = e.x;
	mouseY = e.y;
}

void onMouseWheel(SDL_MouseWheelEvent e)
{

}

void onWindowEvent(SDL_WindowEvent e)
{
	switch (e.event)
	{
	case SDL_WINDOWEVENT_SHOWN:
	case SDL_WINDOWEVENT_HIDDEN:
		break;
	case SDL_WINDOWEVENT_EXPOSED:
		draw();
		break;
	case SDL_WINDOWEVENT_MOVED:
		break;
	case SDL_WINDOWEVENT_RESIZED:
		windowW = e.data1;
		windowH = e.data2;
		break;
	case SDL_WINDOWEVENT_MINIMIZED:
	case SDL_WINDOWEVENT_MAXIMIZED:
	case SDL_WINDOWEVENT_ENTER:
	case SDL_WINDOWEVENT_LEAVE:
	case SDL_WINDOWEVENT_FOCUS_GAINED:
	case SDL_WINDOWEVENT_FOCUS_LOST:
	case SDL_WINDOWEVENT_CLOSE:
	default:
	}
}
