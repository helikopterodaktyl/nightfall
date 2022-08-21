import 'package:flame/effects.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flame/palette.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/widgets.dart';
import 'package:flame/components.dart';
import 'package:flame/input.dart';
import 'package:flame/collisions.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flame_audio/flame_audio.dart';

enum GameState { MENU, CREDITS, GAMEPLAY, OUTRO }

GameState currentGameState = GameState.MENU;

Sprite? sLeft, sRight;
SpriteComponent? player;
List<SpriteComponent> spiders = [];
List<SpriteComponent> checkpoints = [];
Checkpoint? activeCheckpoint;
List<List<dynamic>> fields = [];
bool moveLeft = false;
bool moveRight = false;
bool jumping = false;
bool jumpButton = false;
bool jumpButtonHeld = false;
bool killPlayer = false;
num velocityY = 0;
int curSelection = 0;
const tileSize = 64;

var tipCounter = 0;
var magiTips = [
  "This is the end...\nstep right through",
  "I wouldn't touch those\nif I were you",
  "← → to move\n↑ to jump",
  "Yikes!\nAvoid those spikes",
  "Platforms?\nHow original",
];

const SPIDER = 268;
const FAST_SPIDER = 269;
const PLAYER = 354;
const BAT = 410;
const CHECKPOINT_INACTIVE = 449;
const CHECKPOINT_ACTIVE = 401;
const STAND = 400;
const MAGI = 120;
const EXCLAMATION = 660;
const SPIKES = 22;
const EXIT = 691;
const DOORWAY1 = 825;
const DOORWAY2 = 777;
const DOORWAY3 = 873;

class Checkpoint extends SpriteComponent with CollisionCallbacks {
  bool active = false;
  Sprite? spriteActive;
  Sprite? spriteInactive;

  @override
  void onCollision(Set<Vector2> points, PositionComponent other) {
    super.onCollision(points, other);
    if (other is Player) {
      activeCheckpoint?.deactivate();
      activate();
    }
  }

  void activate() {
    active = true;
    sprite = spriteActive;
    activeCheckpoint = this;
  }

  void deactivate() {
    active = false;
    sprite = spriteInactive;
    activeCheckpoint = null;
  }

  Future<void> onLoad() async {
    add(RectangleHitbox());
  }
}

class Magi extends SpriteComponent with CollisionCallbacks {
  String tip = "";
  Sprite? exclamationSprite;
  bool displayTip = false;

  @override
  void onCollisionStart(Set<Vector2> points, PositionComponent other) {
    super.onCollisionStart(points, other);
    if (other is Player) {
      displayTip = true;
    }
  }

  @override
  void onCollision(Set<Vector2> points, PositionComponent other) {
    super.onCollision(points, other);
    if (other is Player) {
      displayTip = true;
    }
  }

  @override
  void onCollisionEnd(PositionComponent other) {
    super.onCollisionEnd(other);
    if (other is Player) {
      displayTip = false;
    }
  }

  @override
  void render(Canvas c) {
    super.render(c);
    if (displayTip) {
      var tp = TextPaint(
          style: TextStyle(
              fontFamily: 'PressStart2P',
              fontSize: 16,
              color: BasicPalette.white.color));
      double offset = 0;
      for (var line in tip.split('\n')) {
        tp.render(c, line, Vector2(tileSize / 2, -80 + offset.toDouble()),
            anchor: Anchor.center);
        offset += 40;
      }
    } else {
      exclamationSprite?.render(c,
          position: Vector2(0, -80), size: Vector2.all(tileSize.toDouble()));
    }
  }

  Future<void> onLoad() async {
    add(RectangleHitbox(size: Vector2(this.size.x / 2, this.size.y * 4)));
  }
}

class Player extends SpriteComponent with CollisionCallbacks {
  @override
  void onCollision(Set<Vector2> points, PositionComponent other) {
    super.onCollision(points, other);
  }

  Future<void> onLoad() async {
    add(CircleHitbox(radius: 16));
  }

  @override
  void render(Canvas c) {
    var a = anchor;
    anchor = Anchor.center;
    super.render(c);
    anchor = a;
  }
}

class Spider extends SpriteComponent with CollisionCallbacks {
  Vector2 origin = Vector2(0, 0);

  @override
  void onCollision(Set<Vector2> points, PositionComponent other) {
    super.onCollision(points, other);
    if (other is Player) {
      killPlayer = true;
      FlameAudio.play('bite-small.wav');
    }
  }

  @override
  void render(Canvas c) {
    super.render(c);
    c.drawLine(
        Offset(this.size.x / 2, this.size.y / 2),
        Offset(this.size.x / 2,
            origin.y - this.positionOf(Vector2.zero()).y - tileSize / 4),
        Paint()..color = BasicPalette.white.color);
  }

  Future<void> onLoad() async {
    add(CircleHitbox());
  }
}

class Bat extends SpriteComponent with CollisionCallbacks {
  @override
  void onCollision(Set<Vector2> points, PositionComponent other) {
    super.onCollision(points, other);
    if (other is Player) {
      killPlayer = true;
      FlameAudio.play('bite-small2.wav');
    }
  }

  Future<void> onLoad() async {
    add(CircleHitbox());
  }
}

class Spikes extends SpriteComponent with CollisionCallbacks {
  @override
  void onCollision(Set<Vector2> points, PositionComponent other) {
    super.onCollision(points, other);
    if (other is Player) {
      killPlayer = true;
      FlameAudio.play('beads.wav');
    }
  }

  Future<void> onLoad() async {
    add(RectangleHitbox(
        position: Vector2(0.0, this.size.y / 2),
        size: Vector2(this.size.x, this.size.y / 2)));
  }
}

class Doorway extends SpriteComponent with CollisionCallbacks {
  @override
  void onCollision(Set<Vector2> points, PositionComponent other) {
    super.onCollision(points, other);
    if (other is Player && currentGameState == GameState.GAMEPLAY) {
      currentGameState = GameState.OUTRO;
    }
  }

  Future<void> onLoad() async {
    add(RectangleHitbox());
  }
}

class MyGame extends FlameGame with KeyboardEvents, HasCollisionDetection {
  @override
  KeyEventResult onKeyEvent(
    RawKeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    final isKeyDown = event is RawKeyDownEvent;
    final isKeyUp = event is RawKeyUpEvent;
    final isLeftArrow = event.logicalKey == LogicalKeyboardKey.arrowLeft;
    final isRightArrow = event.logicalKey == LogicalKeyboardKey.arrowRight;
    final isJumpButton = event.logicalKey == LogicalKeyboardKey.arrowUp;
    jumpButton = keysPressed.contains(LogicalKeyboardKey.arrowUp);

    bool arrowDown =
        isKeyDown && event.logicalKey == LogicalKeyboardKey.arrowDown;
    bool arrowUp = isKeyDown && event.logicalKey == LogicalKeyboardKey.arrowUp;
    bool enter = isKeyDown &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space);

    if (currentGameState == GameState.GAMEPLAY) {
      if (isLeftArrow) {
        if (isKeyDown) {
          moveLeft = true;
          player!.sprite = sLeft;
        }
        if (isKeyUp) {
          moveLeft = false;
        }
        return KeyEventResult.handled;
      }
      if (isRightArrow) {
        if (isKeyDown) {
          moveRight = true;
          player!.sprite = sRight;
        }
        if (isKeyUp) {
          moveRight = false;
        }
        return KeyEventResult.handled;
      }
      if (isJumpButton) {
        if (isKeyDown) {
          jumpButtonHeld = true;
        }
        if (isKeyUp) {
          jumpButtonHeld = false;
        }
        return KeyEventResult.handled;
      }
      if (jumpButton) {
        return KeyEventResult.handled;
      }
    } else if (currentGameState == GameState.CREDITS) {
      if (enter) {
        currentGameState = GameState.MENU;
        return KeyEventResult.handled;
      }
    } else if (currentGameState == GameState.MENU) {
      if (arrowDown) {
        curSelection = 1;
      }
      if (arrowUp) {
        curSelection = 0;
      }
      if (enter) {
        if (curSelection == 0) {
          currentGameState = GameState.GAMEPLAY;
          FlameAudio.bgm.play("creep.mp3", volume: 0.25);
        } else {
          currentGameState = GameState.CREDITS;
        }
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  void render(Canvas c) {
    if (currentGameState == GameState.MENU) {
      var tp = TextPaint(
          style: TextStyle(
              fontFamily: 'PressStart2P',
              fontSize: 32,
              color: BasicPalette.white.color));
      tp.render(c, "NIGHTFALL", Vector2(size.x / 2, size.y / 4),
          anchor: Anchor.center);

      var tp2 = TextPaint(
          style: TextStyle(
              fontFamily: 'PressStart2P',
              fontSize: 24,
              color: BasicPalette.white.color));
      tp2.render(c, "Play", Vector2(size.x / 2, size.y / 2),
          anchor: Anchor.center);
      tp2.render(c, "Credits", Vector2(size.x / 2, size.y / 2 + 96),
          anchor: Anchor.center);
      if (curSelection == 0) {
        Rect rr = Rect.fromCenter(
            center: Offset(size.x / 2, size.y / 2), width: 400, height: 64);
        Paint p = BasicPalette.white.paint();
        p.style = PaintingStyle.stroke;
        c.drawRect(rr, p);
      }
      if (curSelection == 1) {
        Rect rr = Rect.fromCenter(
            center: Offset(size.x / 2, size.y / 2 + 96),
            width: 400,
            height: 64);
        Paint p = BasicPalette.white.paint();
        p.style = PaintingStyle.stroke;
        c.drawRect(rr, p);
      }
    } else if (currentGameState == GameState.CREDITS) {
      var tp = TextPaint(
          style: TextStyle(
              fontFamily: 'PressStart2P',
              fontSize: 32,
              color: BasicPalette.white.color));
      tp.render(c, "NIGHTFALL", Vector2(size.x / 2, size.y / 4),
          anchor: Anchor.center);

      var tp2 = TextPaint(
          style: TextStyle(
              fontFamily: 'PressStart2P',
              fontSize: 16,
              color: BasicPalette.white.color));
      var tp3 = TextPaint(
          style: TextStyle(
              fontFamily: 'PressStart2P',
              fontSize: 12,
              color: BasicPalette.white.color));

      tp2.render(
          c, "1-Bit Pack by Kenney", Vector2(size.x / 2, size.y / 2 - 16),
          anchor: Anchor.center);
      tp3.render(c, "https://www.kenney.nl/assets/bit-pack",
          Vector2(size.x / 2, size.y / 2 + 16),
          anchor: Anchor.center);

      tp2.render(c, "Font Press Start 2P by CodeMan38",
          Vector2(size.x / 2, size.y / 2 + 64),
          anchor: Anchor.center);
      tp3.render(c, "https://fonts.google.com/specimen/Press+Start+2P",
          Vector2(size.x / 2, size.y / 2 + 96),
          anchor: Anchor.center);

      tp2.render(
          c, "Music by TokyoGeisha", Vector2(size.x / 2, size.y / 2 + 144),
          anchor: Anchor.center);
      tp3.render(c, "https://opengameart.org/content/creepy",
          Vector2(size.x / 2, size.y / 2 + 176),
          anchor: Anchor.center);

      tp2.render(
          c, "SFX by artisticdude", Vector2(size.x / 2, size.y / 2 + 224),
          anchor: Anchor.center);
      tp3.render(c, "https://opengameart.org/content/rpg-sound-pack",
          Vector2(size.x / 2, size.y / 2 + 256),
          anchor: Anchor.center);
    } else if (currentGameState == GameState.OUTRO) {
      var tp = TextPaint(
          style: TextStyle(
              fontFamily: 'PressStart2P',
              fontSize: 32,
              color: BasicPalette.white.color));
      tp.render(c, "NIGHTFALL", Vector2(size.x / 2, size.y / 4),
          anchor: Anchor.center);

      var tp2 = TextPaint(
          style: TextStyle(
              fontFamily: 'PressStart2P',
              fontSize: 24,
              color: BasicPalette.white.color));
      tp2.render(c, "Congratulations", Vector2(size.x / 2, size.y / 2),
          anchor: Anchor.center);
      tp2.render(c, "Glory to you", Vector2(size.x / 2, size.y / 2 + 64),
          anchor: Anchor.center);
      tp2.render(c, "You have bested the devious traps",
          Vector2(size.x / 2, size.y / 2 + 128),
          anchor: Anchor.center);
      tp2.render(c, "You are the ultimate champion",
          Vector2(size.x / 2, size.y / 2 + 192),
          anchor: Anchor.center);
    } else {
      c.translate(0.5, 0.5);
      super.render(c);
      c.translate(-0.5, -0.5);
    }
  }

  @override
  void update(double delta) {
    //if (currentGameState != GameState.GAMEPLAY) return;
    super.update(delta);

    camera.update(delta);
    if (killPlayer) {
      player!.position = activeCheckpoint!.position;
      //player!.position.y += tileSize / 2 - 1;
      jumping = false;
      velocityY = 0;
      killPlayer = false;
    }

    if (jumpButton && !jumping) {
      jumping = true;
      velocityY = -8;
    }

    var newPosX = player!.position.x / tileSize;
    var newPosY = player!.position.y / tileSize;

    if (jumping) {
      Vector2 gravity = Vector2(0.0, 20.0);

      var gravityCoefficient = 1.5;
      if (jumpButtonHeld && velocityY < 0) {
        gravityCoefficient = 0.5;
      }

      velocityY += gravity.y * gravityCoefficient * delta;

      newPosY += velocityY * delta;

      if (velocityY < 0) {
        if (fields[(newPosY).toInt()][(newPosX + 0.1).toInt()] == -1 &&
            fields[(newPosY).toInt()][(newPosX + 0.9).toInt()] == -1) {
          player!.position.y = newPosY * tileSize;
        } else {
          velocityY = 0;
        }
      } else {
        if (fields[(newPosY + 1).toInt()][(newPosX + 0.1).toInt()] == -1 &&
            fields[(newPosY + 1).toInt()][(newPosX + 0.9).toInt()] == -1) {
          player!.position.y = newPosY * tileSize;
        } else {
          player!.position.y = newPosY.round().toDouble() * tileSize;
          velocityY = 0;
          jumping = false;
        }
      }
    } else {
      if (fields[(newPosY + 1).toInt()][(newPosX + 0.1).toInt()] == -1 &&
          fields[(newPosY + 1).toInt()][(newPosX + 0.9).toInt()] == -1) {
        velocityY = 0;
        jumping = true;
      }
    }

    if (moveRight) {
      newPosX = newPosX + 8.0 * delta;

      if (fields![newPosY.toInt()][(newPosX + 0.99).toInt()] == -1 &&
          fields![(newPosY + 0.9).toInt()][(newPosX + 0.99).toInt()] == -1) {
        player!.position.x = newPosX * tileSize;
      }
    }
    if (moveLeft) {
      newPosX = newPosX - 8.0 * delta;

      if (fields![newPosY.toInt()][newPosX.toInt()] == -1 &&
          fields![(newPosY + 0.9).toInt()][newPosX.toInt()] == -1) {
        player!.position.x = newPosX * tileSize;
      }
    }
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    FlameAudio.bgm.initialize();
    await FlameAudio.audioCache
        .loadAll(['bite-small2.wav', 'bite-small3.wav', 'beads.wav']);
    Flame.images.loadAll(<String>[
      'monochrome_transparent_packed.png',
      'player.png',
      'player2.png'
    ]);
    if (kIsWeb) {
      var req = await http.get(Uri.parse('assets/tiles/map1.csv'));
      fields = CsvToListConverter().convert(req.body, shouldParseNumbers: true);
    } else {
      var input = new File('assets/tiles/map1.csv').openRead();

      fields = await input
          .transform(utf8.decoder)
          .transform(new CsvToListConverter())
          .toList();
    }

    final spritesheet = SpriteSheet(
      image: await Flame.images.load("monochrome_transparent_packed.png"),
      srcSize: Vector2.all(16.0),
    );

    final ts = Vector2.all(tileSize.toDouble());
    for (int y = 0; y < fields.length; y++) {
      for (int x = 0; x < fields[0].length; x++) {
        if (fields[y][x] != -1) {
          var f = fields[y][x];

          if (f == PLAYER) {
            sLeft = Sprite(await Flame.images.load("player2.png"));
            sRight = Sprite(await Flame.images.load("player.png"));
            var tile = Player()
              ..size = ts
              ..sprite = sRight
              ..position = Vector2(x.toDouble(), y.toDouble())
                  .scaled(tileSize.toDouble())
              ..angle = 0;
            add(tile);
            fields[y][x] = -1;
            player = tile;
            camera.followVector2(player!.position);
          } else if (f == CHECKPOINT_INACTIVE) {
            var tile = Checkpoint()
              ..size = ts
              ..spriteActive = spritesheet.getSpriteById(CHECKPOINT_ACTIVE)
              ..spriteInactive = spritesheet.getSpriteById(CHECKPOINT_INACTIVE)
              ..sprite = spritesheet.getSpriteById(CHECKPOINT_INACTIVE)
              ..position = Vector2(x.toDouble(), y.toDouble())
                  .scaled(tileSize.toDouble())
              ..angle = 0;
            add(tile);
            fields[y][x] = -1;
            checkpoints.add(tile);
          } else if (f == SPIDER || f == FAST_SPIDER) {
            int spinLength = 0;
            while (fields[y + spinLength + 1][x] == -1) {
              spinLength++;
            }
            var spiderSpeed = f == SPIDER ? 1.0 : 0.5;
            fields[y][x] = -1;
            var tile = Spider()
              ..size = ts
              ..sprite = spritesheet.getSpriteById(f)
              ..position = Vector2(x.toDouble(), y.toDouble())
                  .scaled(tileSize.toDouble())
              ..angle = 0;
            tile.origin = tile.absolutePosition;
            add(tile);
            tile.add(MoveAlongPathEffect(
                Path()
                  ..lineTo(0, spinLength.toDouble() * tileSize)
                  ..lineTo(0, 0),
                EffectController(
                    duration: spinLength.toDouble() * spiderSpeed,
                    infinite: true)));
            spiders.add(tile);
          } else if (f == BAT) {
            Path path = Path();
            int pathLengthVertical = 0;
            while (fields[y - pathLengthVertical - 1][x] == -1) {
              pathLengthVertical++;
            }
            path.relativeLineTo(0, -pathLengthVertical * tileSize.toDouble());
            int pathLengthHorizontal = 0;
            while (fields[y - pathLengthVertical]
                    [x - pathLengthHorizontal - 1] ==
                -1) {
              pathLengthHorizontal++;
            }
            path.relativeLineTo(-pathLengthHorizontal * tileSize.toDouble(), 0);
            path.relativeLineTo(0, pathLengthVertical * tileSize.toDouble());
            path.relativeLineTo(pathLengthHorizontal * tileSize.toDouble(), 0);
            fields[y][x] = -1;
            var tile = Bat()
              ..size = ts
              ..sprite = spritesheet.getSpriteById(f)
              ..position = Vector2(x.toDouble(), y.toDouble())
                  .scaled(tileSize.toDouble())
              ..angle = 0;
            add(tile);
            tile.add(MoveAlongPathEffect(
                path,
                EffectController(
                    duration:
                        (pathLengthVertical + pathLengthHorizontal).toDouble() *
                            0.5,
                    infinite: true)));
          } else if (f == SPIKES) {
            fields[y][x] = -1;
            var tile = Spikes()
              ..size = ts
              ..sprite = spritesheet.getSpriteById(f)
              ..position = Vector2(x.toDouble(), y.toDouble())
                  .scaled(tileSize.toDouble())
              ..angle = 0;
            add(tile);
          } else if (f == DOORWAY1 || f == DOORWAY2 || f == DOORWAY3) {
            fields[y][x] = -1;
            var tile = Doorway()
              ..size = ts
              ..sprite = spritesheet.getSpriteById(f)
              ..position = Vector2(x.toDouble(), y.toDouble())
                  .scaled(tileSize.toDouble())
              ..angle = 0;
            add(tile);
          } else if (f == MAGI) {
            var tile = Magi()
              ..size = ts
              ..sprite = spritesheet.getSpriteById(f)
              ..exclamationSprite = spritesheet.getSpriteById(EXCLAMATION)
              ..position = Vector2(x.toDouble(), y.toDouble())
                  .scaled(tileSize.toDouble())
              ..angle = 0
              ..tip = magiTips[tipCounter++];
            add(tile);
            fields[y][x] = -1;
            checkpoints.add(tile);
          } else {
            if (f == STAND) {
              fields[y][x] = -1;
            }
            var tile = SpriteComponent()
              ..size = ts
              ..sprite = spritesheet.getSpriteById(f)
              ..position = Vector2(x.toDouble(), y.toDouble())
                  .scaled(tileSize.toDouble())
              ..angle = 0;
            add(tile);
          }
        }
      }
    }
  }
}

void main() {
  final game = MyGame();
  runApp(GameWidget(game: game));
}
