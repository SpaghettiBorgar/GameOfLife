import std.stdio;
import etc.linux.memoryerror;
import bindbc.sdl;
import std.string;
import std.typecons : Tuple, tuple;
import std.algorithm.iteration;
import std.algorithm.mutation : swap;
import std.conv : to;
import std.math.traits;
import std.math.rounding;

/// Exception for SDL related issues
class SDLException : Exception
{
	/// Creates an exception from SDL_GetError()
	this(string file = __FILE__, size_t line = __LINE__) nothrow @nogc
	{
		super(cast(string) SDL_GetError().fromStringz, file, line);
	}
}

alias ChunkCoord = Tuple!(int, int);
alias CellCoord = Tuple!(int, int);
immutable auto WHITE = SDL_Color(0xFF, 0xFF, 0xFF, 0xFF);

class Chunk
{
	int cx;
	int cy;
	int x_off;
	int y_off;
	ubyte[CHUNKSIZE][CHUNKSIZE] data;
	ubyte[CHUNKSIZE][CHUNKSIZE] newdata;
	bool processed;
	ubyte emptyIterations;

	bool borderL = true, borderR = true, borderU = true, borderD = true;

	this(int x, int y)
	{
		this.cx = x;
		this.cy = y;
		this.x_off = x * CHUNKSIZE;
		this.y_off = y * CHUNKSIZE;
	}

	void iterate()
	{
		uint emptycells = 0;

		void processOuter(int x, int y)
		{
			void checkBorders()
			{
				if (borderL && x == 0)
				{
					touchChunk(cx - 1, cy);
					borderL = false;
				}
				else if (borderR && x == CHUNKSIZE - 1)
				{
					touchChunk(cx + 1, cy);
					borderR = false;
				}
				if (borderU && y == 0)
				{
					touchChunk(cx, cy - 1);
					borderU = false;
				}
				else if (borderU && y == CHUNKSIZE - 1)
				{
					touchChunk(cx, cy + 1);
					borderD = false;
				}
			}

			auto count = ringSum!getCellN(x_off + x, y_off + y);

			if (count < 2 || count > 3)
				newdata[x][y] = 0;
			else if (count == 3)
			{
				newdata[x][y] = 1;
				if (!data[x][y])
					checkBorders();
			}
			else
				newdata[x][y] = data[x][y];

			emptycells += !newdata[x][y];
		}

		void processInner(int x, int y)
		{
			auto count = ringSum!((int x, int y) => data[x][y])(x, y);

			if (count < 2 || count > 3)
				newdata[x][y] = 0;
			else if (count == 3)
				newdata[x][y] = 1;
			else
				newdata[x][y] = data[x][y];

			emptycells += !newdata[x][y];
		}

		foreach (x; 1 .. CHUNKSIZE - 1)
			foreach (y; 1 .. CHUNKSIZE - 1)
				processInner(x, y);

		foreach (x; 0 .. CHUNKSIZE)
		{
			processOuter(x, 0);
			processOuter(x, CHUNKSIZE - 1);
		}
		foreach (y; 1 .. CHUNKSIZE - 1)
		{
			processOuter(0, y);
			processOuter(CHUNKSIZE - 1, y);
		}

		assert(emptycells <= CHUNKSIZE * CHUNKSIZE);
		if (emptycells == CHUNKSIZE * CHUNKSIZE)
			emptyIterations++;
		else
			emptyIterations = 0;

	}

	void finish()
	{
		if (emptyIterations >= 5)
			deleteChunk(cx, cy);
		swap(data, newdata);
	}
}



class Figure
{
	const uint width;
	const uint height;
	ubyte[][] data;

	this(uint width, uint height)
	{
		this.width = width;
		this.height = height;
		this.data = new ubyte[][](height, width);
	}

	this(string filePath)
	{
		auto file = new File(getResourcePath("figures/" ~ filePath ~ ".txt"));
		auto byLine = file.byLine();
		int row = 0;
		this.width = cast(uint) byLine.front().length;
		this.data = new ubyte[][](file.size() / (this.width+1));
		foreach (line; byLine)
		{
			this.data[row] = new ubyte[](this.width);
			foreach(col, c; line)
			{
				if(c == '#')
					this.data[row][col] = 1;
				else if(c == ' ')
					this.data[row][col] = 0;
				
			}
			row++;
		}
		this.height = cast(uint) this.data.length;
	}
}

int mod(int a, int b) pure
{
	return (a % b + b) % b;
}

import std.math : pow;

immutable int CHUNKSIZEPOW = 6;
immutable int CHUNKSIZE = pow(2, CHUNKSIZEPOW);

TTF_Font* font;

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
int shiftX;
int shiftY;
bool active = false;

Chunk[ChunkCoord] field;
uint iteration;
bool drawDebug = true;

void main()
{
	registerMemoryErrorHandler();

	writeln(sdlSupport);

	if (loadSDL() != sdlSupport)
		writeln("Error loading SDL library");

	writeln(sdlTTFSupport);

	if (loadSDLTTF() != sdlTTFSupport)
		writeln("Error loading SDL TTF library");

	if (SDL_Init(SDL_INIT_VIDEO) < 0)
		throw new SDLException();

	if (TTF_Init() < 0)
		throw new SDLException();

	scope (exit)
		SDL_Quit();

	windowW = 800;
	windowH = 600;
	auto window = SDL_CreateWindow("SDL Application", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
		windowW, windowH, SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE);
	if (!window)
		throw new SDLException();

	sdlr = SDL_CreateRenderer(window, -1, 0 | SDL_RENDERER_PRESENTVSYNC);

	SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "1");

	font = TTF_OpenFont(getResourcePath("fonts/NotoSansMono.ttf").toStringz, 14);

	init();

	running = true;
	while (running)
	{
		pollEvents();
		tick();
		draw();
	}
}

void init()
{
	iteration = 0;
	
	foreach (x; -10 .. 10)
	{
		foreach (y; -5 .. 5)
		{
			Chunk ch = new Chunk(x, y);
			field[tuple(x, y)] = ch;
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
	}
	paintFigure(new Figure("qrcode"), 20, 20);
}


void paintFigure(Figure fig, int x_off, int y_off)
{
	import std.range;
	foreach(y, row; fig.data.enumerate(y_off)) {
		foreach(x, c; row.enumerate(x_off)) {
			*getCellP(cast(int) x, cast(int) y) = c;
		}
	}
}

import std.traits;

ubyte sign(T)(T val) if (isNumeric!T)
{
	return !!(val & (1 << (T.sizeof * 8 - 1)));
}

auto ringSum(alias fun, N)(N x, N y) if (isCallable!fun && isNumeric!N)
{
	// dfmt off
	return (
		fun(x - 1, y - 1) + fun(x    , y - 1) + fun(x + 1, y - 1) +
		fun(x - 1, y    ) +                     fun(x + 1, y    ) +
		fun(x - 1, y + 1) + fun(x    , y + 1) + fun(x + 1, y + 1)) ;
	// dfmt on
}

ubyte getNeighbours(int x, int y)
{
	return cast(ubyte) ringSum!getCellN(x, y);
}

Chunk* getChunk(int x, int y)
{
	return cell2chunk(x, y) in field;
}

ubyte* getCellP(int x, int y)
{
	Chunk* chunk = getChunk(x, y);
	return chunk is null ? null : &chunk.data[x.mod(CHUNKSIZE)][y.mod(CHUNKSIZE)];
}

ubyte getCell(int x, int y)
{
	Chunk* chunk = getChunk(x, y);
	return chunk is null ? 0 : chunk.data[x - chunk.x_off][y - chunk.y_off];
}

ubyte getCellN(int x, int y)
{
	Chunk* chunk = getChunk(x, y);
	return chunk is null ? 0 : chunk.data[x - chunk.x_off][y - chunk.y_off];
}

ChunkCoord screen2cell(int x, int y)
{
	return tuple((x - shiftX - 1) / cSize - sign(x - shiftX),
		(y - shiftY - 1) / cSize - sign(y - shiftY));
}

ChunkCoord cell2chunk(int x, int y) pure
{
	return tuple(
		x >> CHUNKSIZEPOW,
		y >> CHUNKSIZEPOW);
}

void touchChunk(int x, int y)
{
	field.require(tuple(x, y), new Chunk(x, y));
}

void deleteChunk(int x, int y)
{
	auto tup = tuple(x, y);
	field.remove(tup);
	if (tuple(x - 1, y) in field)
		field[tuple(x - 1, y)].borderR = true;
	if (tuple(x + 1, y) in field)
		field[tuple(x + 1, y)].borderL = true;
	if (tuple(x, y - 1) in field)
		field[tuple(x, y - 1)].borderD = true;
	if (tuple(x, y + 1) in field)
		field[tuple(x, y + 1)].borderU = true;
}

void tick()
{
	if (mouseL)
	{
		auto cellCoords = screen2cell(mouseX, mouseY);
		auto chunkCoords = cell2chunk(cellCoords[0], cellCoords[1]);
		touchChunk(chunkCoords[0], chunkCoords[1]);
		ubyte* cell = getCellP(cellCoords[0], cellCoords[1]);
		*cell = 1;
	}

	if (active)
		iterate();
}

void iterate()
{
	field.each!(c => c.iterate);
	field.each!(c => c.finish);

	iteration++;	
}

void drawText(string text, int x, int y, SDL_Color col)
{
	SDL_Surface* surf = TTF_RenderUTF8_Blended(font, text.toStringz, col);
	SDL_Texture* tex = sdlr.SDL_CreateTextureFromSurface(surf);
	surf.SDL_FreeSurface();
	sdlr.SDL_RenderCopy(tex, null, new SDL_Rect(x, y, surf.w, surf.h));
	tex.SDL_DestroyTexture();
}

void draw()
{
	import std.datetime.stopwatch;

	static uint frame;
	static float fps;
	static auto sw = StopWatch(AutoStart.no);
	if (!sw.running)
		sw.start();

	sdlr.SDL_SetRenderDrawColor(0, 0, 0, 255);
	sdlr.SDL_RenderClear();

	auto chunkRange = tuple(screen2cell(0, 0).expand.cell2chunk,
		screen2cell(windowW, windowH).expand.cell2chunk);
	uint chunksRendered;

	foreach (chunk; field)
	{
		if (chunk.cx < chunkRange[0][0] || chunk.cx > chunkRange[1][0] || chunk.cy < chunkRange[0][1] || chunk.cy > chunkRange[1][1])
			continue;
		foreach (x; 0 .. CHUNKSIZE)
		{
			foreach (y; 0 .. CHUNKSIZE)
			{
				if (chunk.data[x][y])
				{
					sdlr.SDL_SetRenderDrawColor(255, 255, 255, 255);
					sdlr.SDL_RenderFillRect(new SDL_Rect((chunk.x_off + x) * cSize + shiftX,
							(chunk.y_off + y) * cSize + shiftY, cSize, cSize));
				}
			}
		}
		if (drawDebug)
		{
			sdlr.SDL_SetRenderDrawColor(0, 255, 0, 128);
			sdlr.SDL_RenderDrawRect(new SDL_Rect(
					chunk.cx * CHUNKSIZE * cSize + shiftX,
					chunk.cy * CHUNKSIZE * cSize + shiftY,
					CHUNKSIZE * cSize, CHUNKSIZE * cSize));
		}
		chunksRendered++;
	}
	drawText(fps.format!"%.2f fps", 0, 0, SDL_Color(0x00, 0xFF, 0x00, 0xFF));
	drawText(iteration.format!"iteration %d", 0, 20, SDL_Color(0xFF, 0xFF, 0x00, 0xFF));
	if (drawDebug)
	{
		drawText(format!"%d chunks / %d cells"(field.length, (field.length * CHUNKSIZE * CHUNKSIZE)), 0, 40, WHITE);
		drawText(chunksRendered.format!"%d chunks visible", 0, 60, WHITE);
		auto cellCoords = screen2cell(mouseX, mouseY);
		auto chunkCoords = cellCoords.expand.cell2chunk;
		drawText(format!"%(%(%d %d%) / %)"([
				cellCoords,
				chunkCoords,
				tuple(cellCoords[0].mod(CHUNKSIZE), cellCoords[1].mod(CHUNKSIZE))
			]), 0, 80, WHITE);
	}
	if (sw.peek.total!"msecs" >= 500)
	{
		fps = cast(float) frame / sw.peek.total!"msecs" * 1000;
		frame = 0;
		sw.reset();
	}

	sdlr.SDL_RenderPresent();
	frame++;
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
			writeln("Unhandled event: ", cast(SDL_EventType) event.type);
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
	case SDLK_q:
		quit();
		break;
	case SDLK_r:
		init();
		break;
	case SDLK_s:
		iterate();
		break;
	case SDLK_SPACE:
		active = !active;
		break;
	case SDLK_F3:
		drawDebug = !drawDebug;
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

	if (mouseR)
	{
		shiftX += e.xrel;
		shiftY += e.yrel;
	}
	if (mouseL)
	{
		auto cellCoords = screen2cell(mouseX, mouseY);
		ubyte* cell = getCellP(cellCoords[0], cellCoords[1]);
		if (cell !is null)
			*cell = 1;
	}
}

void onMouseWheel(SDL_MouseWheelEvent e)
{
	import std.algorithm.comparison : clamp;

	auto oldPoint = screen2cell(mouseX, mouseY);
	cSize = cast(ubyte) clamp(cSize + e.y, 1, 128);
	auto newPoint = screen2cell(mouseX, mouseY);
	shiftX += (newPoint[0] - oldPoint[0]) * cSize;
	shiftY += (newPoint[1] - oldPoint[1]) * cSize;
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

string getResourcePath(string name)
{
	return "./res/" ~ name;
}
