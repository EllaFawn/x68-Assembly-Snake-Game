; Project: The Snake Fella
; Date Created: 03/03/2026
* Description: Snake Game with Alternative Physics systems.
*
*   KEYBOARD NOTE:
*   Input is handled by polling task 19 inside READ_KEYS each
*   game tick. No interrupt vector or ENABLEKEYBOARD is used,
*   avoiding the SSP crash caused by RTE with no interrupt frame.
*
*   PHYSICS FEATURES:
*   1. DATA VALIDATION  - Difficulty select. Only 1/2/3 accepted.
*   2. RESOURCE USAGE   - Fuel drains at 0.5 per tick (every other
*                         tick via FUEL_TICK toggle). Restored by
*                         eating food. Zero fuel = dead.
*   3. HANDLING DAMAGE  - Wall Wrap + Shields. Crossing a wall
*                         teleports the snake and costs one shield.
*                         Zero shields on impact = dead.
*   4. DYNAMIC EVENTS   - Solar Flare. 1/32 chance per tick.
*                         2-second flashing warning before it
*                         activates. 7-second cooldown after it
*                         ends before it can trigger again.
*                         Controls reversed while active.
*                         Border: flashing yellow/green warning,
*                         solid yellow while active.
*   5. SPEED BOOST      - Space bar. 5-tick burst, halves delay.
*                         Costs extra fuel per tick.
*
*   Arrow Keys to steer, Space to Boost, ESC to quit.
*-----------------------------------------------------------

    ORG     $1000

START:

*-----------------------------------------------------------
* Section       : Trap Codes
*-----------------------------------------------------------

TC_SCREEN   EQU         33
TC_KEYCODE  EQU         19
TC_DBL_BUF  EQU         92
TC_CURSR_P  EQU         11
TC_EXIT     EQU         09

*-----------------------------------------------------------
* Section       : Game Constants
*-----------------------------------------------------------

CELL_SIZE   EQU         20
GRID_MAX    EQU         32
SCREEN_PX   EQU         640

ESCAPE_LO   EQU         $71         ; 'q' lowercase - Easy68k swallows $1B
ESCAPE_HI   EQU         $51         ; 'Q' uppercase - accept either
SPACE       EQU         $20

DIR_LEFT    EQU         1
DIR_UP      EQU         2
DIR_RIGHT   EQU         3
DIR_DOWN    EQU         4

POINTS      EQU         1
OPPS_INDEX  EQU         02
MAX_SNAKE   EQU         30

*-----------------------------------------------------------
* Section       : Speed Constants
*-----------------------------------------------------------

SPEED_INC   EQU         $5000
MIN_DELAY   EQU         $8000

*-----------------------------------------------------------
* Section       : Difficulty Constants
*-----------------------------------------------------------

DIFF_EASY   EQU         1
DIFF_MED    EQU         2
DIFF_HARD   EQU         3

DLY_EASY    EQU         $3FFFF
DLY_MED     EQU         $25000
DLY_HARD    EQU         $10000

FUEL_EASY   EQU         100
FUEL_MED    EQU         75
FUEL_HARD   EQU         50

SHLD_EASY   EQU         3
SHLD_MED    EQU         2
SHLD_HARD   EQU         1

*-----------------------------------------------------------
* Section       : Alternative Physics Constants
*-----------------------------------------------------------

* Fuel
* FUEL_TICK toggle means drain of 1 every OTHER tick = 0.5/tick
FUEL_EAT    EQU         20          ; Fuel restored per food eaten
FUEL_MAX    EQU         100

* Solar Flare
* Tick counts are calibrated against the Easy/Medium delay loop.
* At DLY_EASY (~$3FFFF loop) ~8 ticks/sec -> 16 ticks ~ 2 sec warning
*                                           -> 56 ticks ~ 7 sec cooldown
FLARE_TICKS     EQU     25          ; Duration of active flare (ticks)
FLARE_WARN_TICKS EQU    16          ; Warning flash before activation (~2 sec)
FLARE_COOL_TICKS EQU    56          ; Cooldown after flare ends (~7 sec)

* Boost
BOOST_TICKS EQU         5
BOOST_EXTRA EQU         3

*-----------------------------------------------------------
* Section       : Graphic Colours  ($00BBGGRR in Easy68k)
*-----------------------------------------------------------

WHITE       EQU         $00FFFFFF
SNAKEGREEN  EQU         $0000CC00
RED         EQU         $000000CC
DARKGREEN   EQU         $00003300
YELLOW      EQU         $0000CCCC

*-----------------------------------------------------------
* Subroutine    : Initialise
*-----------------------------------------------------------

INITIALISE:

    JSR     SETSCREEN

    BSR     DIFFICULTY_SELECT
    BSR     APPLY_DIFFICULTY

    BSR     OPPS_LOAD

    CLR.L   D1
    MOVE.L  D1,         PLAYER_SCORE

    MOVE.B  #16,        SNAKE_X
    MOVE.B  #16,        SNAKE_Y
    MOVE.B  #DIR_RIGHT, SNAKE_DIR

    MOVE.B  #1,         SNAKE_LEN
    MOVE.B  #16,        BODY_X
    MOVE.B  #16,        BODY_Y

    ; Clear all physics flags / timers
    CLR.B   FUEL_TICK
    CLR.B   FLARE_ACTIVE
    CLR.B   FLARE_TIMER
    CLR.B   FLARE_WARNING
    CLR.B   FLARE_WARN_TIMER
    CLR.B   FLARE_COOLDOWN
    CLR.B   WARN_FLASH
    CLR.B   BOOST_ACTIVE
    CLR.B   BOOST_TIMER

    JSR     PLACEFOOD

    MOVE.B  #TC_DBL_BUF,D0
    MOVE.B  #17,        D1
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$FF00,     D1
    TRAP    #15

*-----------------------------------------------------------
* Subroutine    : Game / GameLoop
*-----------------------------------------------------------

GAME:
    BSR     DRAW_TITLE

GAMELOOP:
    BSR     DYNAMIC_DELAY
    BSR     READ_KEYS
    BSR     UPDATE
    BSR     CHECK_BOUNDS_WRAP
    BSR     CHECK_SELF_COLLISION    
    BSR     CHECK_FOOD
    BSR     TICK_PHYSICS
    BSR     DRAW
    BRA     GAMELOOP

*-----------------------------------------------------------
* Subroutine    : Difficulty Select
* Description   : DATA VALIDATION - only 1, 2 or 3 accepted.
*                 All other keys rejected silently.
*-----------------------------------------------------------

DIFFICULTY_SELECT:

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$FF00,     D1
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$1408,     D1          ; Col 20, Row 8
    TRAP    #15
    LEA     DIFF_TITLE_MSG,A1
    MOVE    #13,        D0
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$140A,     D1          ; Col 20, Row 10
    TRAP    #15
    LEA     DIFF_SEL_MSG,A1
    MOVE    #13,        D0
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$100C,     D1          ; Col 16, Row 12
    TRAP    #15
    LEA     DIFF_EASY_MSG,A1
    MOVE    #13,        D0
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$100D,     D1          ; Col 16, Row 13
    TRAP    #15
    LEA     DIFF_MED_MSG,A1
    MOVE    #13,        D0
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$100E,     D1          ; Col 16, Row 14
    TRAP    #15
    LEA     DIFF_HARD_MSG,A1
    MOVE    #13,        D0
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$1210,     D1          ; Col 18, Row 16
    TRAP    #15
    LEA     DIFF_PRMPT_MSG,A1
    MOVE    #13,        D0
    TRAP    #15

DIFF_WAIT:
    CLR.L   D1
    MOVE.B  #TC_KEYCODE,D0
    TRAP    #15
    CMP.B   #$31,       D1          ; '1'
    BEQ     DIFF_CHOOSE_1
    CMP.B   #$32,       D1          ; '2'
    BEQ     DIFF_CHOOSE_2
    CMP.B   #$33,       D1          ; '3'
    BEQ     DIFF_CHOOSE_3
    BRA     DIFF_WAIT

DIFF_CHOOSE_1:
    MOVE.B  #DIFF_EASY, DIFFICULTY
    BRA     DIFF_DONE
DIFF_CHOOSE_2:
    MOVE.B  #DIFF_MED,  DIFFICULTY
    BRA     DIFF_DONE
DIFF_CHOOSE_3:
    MOVE.B  #DIFF_HARD, DIFFICULTY

DIFF_DONE:
    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$FF00,     D1
    TRAP    #15
    RTS

*-----------------------------------------------------------
* Subroutine    : Apply Difficulty
*-----------------------------------------------------------

APPLY_DIFFICULTY:
    MOVE.B  DIFFICULTY, D1
    CMP.B   #DIFF_EASY, D1
    BEQ     APD_EASY
    CMP.B   #DIFF_MED,  D1
    BEQ     APD_MED

APD_HARD:
    MOVE.L  #DLY_HARD,  DELAY_COUNT
    MOVE.B  #FUEL_HARD, FUEL
    MOVE.B  #SHLD_HARD, SHIELD
    RTS

APD_MED:
    MOVE.L  #DLY_MED,   DELAY_COUNT
    MOVE.B  #FUEL_MED,  FUEL
    MOVE.B  #SHLD_MED,  SHIELD
    RTS

APD_EASY:
    MOVE.L  #DLY_EASY,  DELAY_COUNT
    MOVE.B  #FUEL_EASY, FUEL
    MOVE.B  #SHLD_EASY, SHIELD
    RTS

*-----------------------------------------------------------
* Subroutine    : Draw Title
*-----------------------------------------------------------

DRAW_TITLE:
    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$100A,     D1
    TRAP    #15
    LEA     TITLE_MSG,  A1
    MOVE    #13,        D0
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$0C0C,     D1
    TRAP    #15
    LEA     CTRL_MSG,   A1
    MOVE    #13,        D0
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$0C0D,     D1
    TRAP    #15
    LEA     BOOST_TIP_MSG,A1
    MOVE    #13,        D0
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$0E0E,     D1
    TRAP    #15
    LEA     QUIT_MSG,   A1
    MOVE    #13,        D0
    TRAP    #15

    JSR     DELAY
    JSR     DELAY
    JSR     DELAY
    JSR     DELAY

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$FF00,     D1
    TRAP    #15
    RTS

*-----------------------------------------------------------
* Subroutine    : Read Keys
* Description   : Polls task 19. Handles ESC, Space (boost),
*                 and arrow keys. SPACE must be checked before
*                 the arrow chain because $20 < $25.
*-----------------------------------------------------------

READ_KEYS:
    CLR.L   D1
    MOVE.B  #TC_KEYCODE,D0
    TRAP    #15

    TST.B   D1
    BEQ     RK_DONE                 ; 0 = no key yet

    ; Easy68k swallows $1B at simulator level so Q/q is used to quit
    CMP.B   #ESCAPE_LO, D1          ; 'q' lowercase ?
    BEQ     EXIT
    CMP.B   #ESCAPE_HI, D1          ; 'Q' uppercase ?
    BEQ     EXIT

    CMP.B   #SPACE,     D1          ; MUST be before arrow chain ($20 < $25)
    BEQ     RK_BOOST
    CMP.B   #$25,       D1
    BEQ     RK_LEFT
    CMP.B   #$26,       D1
    BEQ     RK_UP
    CMP.B   #$27,       D1
    BEQ     RK_RIGHT
    CMP.B   #$28,       D1
    BEQ     RK_DOWN

RK_DONE:
    RTS

RK_LEFT:
    MOVE.B  #DIR_LEFT,  SNAKE_DIR
    RTS
RK_UP:
    MOVE.B  #DIR_UP,    SNAKE_DIR
    RTS
RK_RIGHT:
    MOVE.B  #DIR_RIGHT, SNAKE_DIR
    RTS
RK_DOWN:
    MOVE.B  #DIR_DOWN,  SNAKE_DIR
    RTS

RK_BOOST:
    ; Space toggles boost. Pressing again while active turns it OFF.
    ; Turning ON requires enough fuel for at least one boosted tick.
    TST.B   BOOST_ACTIVE
    BNE     RK_BOOST_OFF            ; Already on: turn off

    ; --- Turn boost ON ---
    MOVE.B  FUEL,       D1
    CMP.B   #BOOST_EXTRA,D1
    BLT     RK_DONE                 ; Not enough fuel: ignore
    MOVE.B  #1,         BOOST_ACTIVE
    MOVE.B  #BOOST_TICKS,BOOST_TIMER
    RTS

RK_BOOST_OFF:
    ; --- Turn boost OFF immediately ---
    CLR.B   BOOST_ACTIVE
    CLR.B   BOOST_TIMER
    RTS

*-----------------------------------------------------------
* Subroutine    : Update
* Description   : Shifts body trail, optionally flips direction
*                 for Solar Flare (active only, not warning),
*                 then moves the head. Syncs body[0].
*-----------------------------------------------------------

UPDATE:
    BSR     SHIFT_BODY

    MOVE.B  SNAKE_DIR,  D1

    ; Reverse controls only while flare is ACTIVE, not during warning
    TST.B   FLARE_ACTIVE
    BEQ     UPDATE_MOVE

    CMP.B   #DIR_LEFT,  D1
    BEQ     UPD_FLIP_R
    CMP.B   #DIR_RIGHT, D1
    BEQ     UPD_FLIP_L
    CMP.B   #DIR_UP,    D1
    BEQ     UPD_FLIP_D
    MOVE.B  #DIR_UP,    D1          ; Was DOWN -> flip UP
    BRA     UPDATE_MOVE

UPD_FLIP_R:
    MOVE.B  #DIR_RIGHT, D1
    BRA     UPDATE_MOVE
UPD_FLIP_L:
    MOVE.B  #DIR_LEFT,  D1
    BRA     UPDATE_MOVE
UPD_FLIP_D:
    MOVE.B  #DIR_DOWN,  D1

UPDATE_MOVE:
    CMP.B   #DIR_LEFT,  D1
    BEQ     DO_MOVE_LEFT
    CMP.B   #DIR_UP,    D1
    BEQ     DO_MOVE_UP
    CMP.B   #DIR_RIGHT, D1
    BEQ     DO_MOVE_RIGHT
    CMP.B   #DIR_DOWN,  D1
    BEQ     DO_MOVE_DOWN
    BRA     UPDATE_STORE_HEAD

DO_MOVE_LEFT:
    SUB.B   #1,         SNAKE_X
    BRA     UPDATE_STORE_HEAD
DO_MOVE_UP:
    SUB.B   #1,         SNAKE_Y
    BRA     UPDATE_STORE_HEAD
DO_MOVE_RIGHT:
    ADD.B   #1,         SNAKE_X
    BRA     UPDATE_STORE_HEAD
DO_MOVE_DOWN:
    ADD.B   #1,         SNAKE_Y

UPDATE_STORE_HEAD:
    MOVE.B  SNAKE_X,    BODY_X
    MOVE.B  SNAKE_Y,    BODY_Y
    RTS

*-----------------------------------------------------------
* Subroutine    : Shift Body
*-----------------------------------------------------------

SHIFT_BODY:
    MOVEM.L D0-D4/A0,   -(SP)

    CLR.L   D0
    MOVE.B  SNAKE_LEN,  D0
    CMP.B   #2,         D0
    BLT     SHIFT_BODY_DONE

    MOVE.B  D0,         D1
    SUB.B   #1,         D1

SHIFT_LOOP_B:
    CLR.L   D2
    MOVE.B  D1,         D2
    CLR.L   D3
    MOVE.B  D1,         D3
    SUB.B   #1,         D3

    LEA     BODY_X,     A0
    ADDA.W  D3,         A0
    MOVE.B  (A0),       D4
    LEA     BODY_X,     A0
    ADDA.W  D2,         A0
    MOVE.B  D4,         (A0)

    LEA     BODY_Y,     A0
    ADDA.W  D3,         A0
    MOVE.B  (A0),       D4
    LEA     BODY_Y,     A0
    ADDA.W  D2,         A0
    MOVE.B  D4,         (A0)

    SUB.B   #1,         D1
    CMP.B   #1,         D1
    BGE     SHIFT_LOOP_B

SHIFT_BODY_DONE:
    MOVEM.L (SP)+,      D0-D4/A0
    RTS

*-----------------------------------------------------------
* Subroutine    : Check Bounds Wrap
* Description   : HANDLING DAMAGE - wall crossing teleports
*                 the snake and costs one shield.
*-----------------------------------------------------------

CHECK_BOUNDS_WRAP:

    CLR.L   D1
    MOVE.B  SNAKE_X,    D1
    CMP.B   #GRID_MAX,  D1
    BGE     WRAP_RIGHT
    CMP.B   #0,         D1
    BLT     WRAP_LEFT

    CLR.L   D1
    MOVE.B  SNAKE_Y,    D1
    CMP.B   #GRID_MAX,  D1
    BGE     WRAP_BOTTOM
    CMP.B   #0,         D1
    BLT     WRAP_TOP

    RTS

WRAP_RIGHT:
    MOVE.B  #0,         SNAKE_X
    BRA     WALL_PENALTY
WRAP_LEFT:
    MOVE.B  #31,        SNAKE_X
    BRA     WALL_PENALTY
WRAP_BOTTOM:
    MOVE.B  #0,         SNAKE_Y
    BRA     WALL_PENALTY
WRAP_TOP:
    MOVE.B  #31,        SNAKE_Y

WALL_PENALTY:
    MOVE.B  SNAKE_X,    BODY_X
    MOVE.B  SNAKE_Y,    BODY_Y

    TST.B   SHIELD
    BEQ     DEAD
    SUB.B   #1,         SHIELD
    BSR     PLAY_OPPS
    RTS

*-----------------------------------------------------------
* Subroutine    : Check Self Collision
* Description   : HANDLING DAMAGE extension.
*                 After the head has moved, compare it against
*                 every body segment from index 2 to LEN-1.
*                 Index 0 is the head itself.
*                 Index 1 is the neck - the cell the head just
*                 left - which is always adjacent and can never
*                 cause a real self-collision, so it is skipped.
*                 On a hit the same shield/dead logic used for
*                 wall contact applies: spend one shield (with
*                 sound) or end the game if shields are empty.
*                 Registers used: D0=length, D1=loop index,
*                 D2=head X, D3=head Y, D4=segment byte, A0=ptr.
*                 All saved and restored via MOVEM.
*-----------------------------------------------------------

CHECK_SELF_COLLISION:
    MOVEM.L D0-D4/A0,   -(SP)

    CLR.L   D0
    MOVE.B  SNAKE_LEN,  D0
    CMP.B   #3,         D0          ; Need at least 3 segments to
    BLT     CSC_DONE                ; be able to collide with body

    CLR.L   D2
    CLR.L   D3
    MOVE.B  SNAKE_X,    D2          ; D2 = head X
    MOVE.B  SNAKE_Y,    D3          ; D3 = head Y

    MOVE.B  #2,         D1          ; Start checking from index 2

CSC_LOOP:
    CLR.L   D4
    LEA     BODY_X,     A0
    ADDA.W  D1,         A0
    MOVE.B  (A0),       D4          ; D4 = BODY_X[i]
    CMP.B   D2,         D4          ; Matches head X?
    BNE     CSC_NEXT

    CLR.L   D4
    LEA     BODY_Y,     A0
    ADDA.W  D1,         A0
    MOVE.B  (A0),       D4          ; D4 = BODY_Y[i]
    CMP.B   D3,         D4          ; Matches head Y?
    BEQ     CSC_HIT                 ; Both match: self-collision!

CSC_NEXT:
    ADD.B   #1,         D1
    CMP.B   D0,         D1          ; Reached LEN?
    BLT     CSC_LOOP

CSC_DONE:
    MOVEM.L (SP)+,      D0-D4/A0
    RTS

CSC_HIT:
    MOVEM.L (SP)+,      D0-D4/A0    ; Restore before branching out
    TST.B   SHIELD
    BEQ     DEAD                    ; No shields left: game over
    SUB.B   #1,         SHIELD      ; Spend one shield
    BSR     PLAY_OPPS               ; Audio cue
    RTS

*-----------------------------------------------------------
* Subroutine    : Check Food
*-----------------------------------------------------------

CHECK_FOOD:
    MOVE.B  SNAKE_X,    D1
    MOVE.B  FOOD_X,     D2
    CMP.B   D1,         D2
    BNE     NO_EAT

    MOVE.B  SNAKE_Y,    D1
    MOVE.B  FOOD_Y,     D2
    CMP.B   D1,         D2
    BNE     NO_EAT

    BSR     PLAY_OPPS
    ADD.L   #POINTS,    PLAYER_SCORE
    JSR     PLACEFOOD

    MOVE.B  FUEL,       D1
    ADD.B   #FUEL_EAT,  D1
    CMP.B   #FUEL_MAX,  D1
    BLE     CF_STORE_FUEL
    MOVE.B  #FUEL_MAX,  D1

CF_STORE_FUEL:
    MOVE.B  D1,         FUEL

    MOVE.B  SNAKE_LEN,  D1
    CMP.B   #MAX_SNAKE, D1
    BGE     CF_NO_GROW
    ADD.B   #1,         SNAKE_LEN

CF_NO_GROW:
    MOVE.L  DELAY_COUNT,D1
    SUB.L   #SPEED_INC, D1
    CMP.L   #MIN_DELAY, D1
    BGE     CF_SPEED_STORE
    MOVE.L  #MIN_DELAY, D1

CF_SPEED_STORE:
    MOVE.L  D1,         DELAY_COUNT

NO_EAT:
    RTS

*-----------------------------------------------------------
* Subroutine    : Tick Physics
* Description   : All alternative physics systems per tick.
*
*   1. FUEL DECAY (0.5 per tick)
*      FUEL_TICK toggles between 0 and 1 each tick.
*      Fuel is only subtracted on the tick where FUEL_TICK
*      flips to 1. This gives an average drain of exactly
*      0.5 per tick without any floating-point arithmetic.
*
*   2. BOOST TICK
*      Costs BOOST_EXTRA fuel per boosted tick.
*      Deactivates when timer or fuel runs out.
*
*   3. SOLAR FLARE (DYNAMIC EVENT)
*      Four distinct states, tested in priority order:
*
*      FLARE_ACTIVE (state 3):
*        Count down FLARE_TIMER. On expiry, zero FLARE_ACTIVE
*        and load FLARE_COOL_TICKS into FLARE_COOLDOWN.
*
*      FLARE_WARNING (state 2):
*        Count down FLARE_WARN_TIMER. On expiry, clear
*        FLARE_WARNING and activate FLARE_ACTIVE with a
*        full FLARE_TICKS countdown. WARN_FLASH toggles
*        each warning tick to drive the border flash.
*
*      FLARE_COOLDOWN (state 1):
*        Count down FLARE_COOLDOWN. While > 0 no new flare
*        can be triggered. No border change.
*
*      IDLE (state 0):
*        Roll a 1/32 chance each tick. On zero result,
*        start FLARE_WARNING and prime FLARE_WARN_TIMER.
*-----------------------------------------------------------

TICK_PHYSICS:

    ; --- 1. Fuel Decay at 0.5 per tick ---
    ; Toggle FUEL_TICK between 0 and 1 each call.
    ; Only drain fuel when it flips to 1 (every other tick).
    MOVE.B  FUEL_TICK,  D1
    EOR.B   #1,         D1          ; Flip low bit: 0->1, 1->0
    MOVE.B  D1,         FUEL_TICK
    TST.B   D1
    BEQ     TP_BOOST                ; This is the 0-tick: skip drain

    ; Drain tick - subtract 1 fuel
    MOVE.B  FUEL,       D1
    SUB.B   #1,         D1
    BCS     TP_FUEL_EMPTY           ; Underflow: was already 0
    MOVE.B  D1,         FUEL
    TST.B   FUEL
    BEQ     TP_FUEL_EMPTY           ; Landed on exactly 0
    BRA     TP_BOOST

TP_FUEL_EMPTY:
    CLR.B   FUEL
    JMP     DEAD

    ; --- 2. Boost Tick ---
TP_BOOST:
    TST.B   BOOST_ACTIVE
    BEQ     TP_FLARE_STATE

    MOVE.B  FUEL,       D1
    CMP.B   #BOOST_EXTRA,D1
    BLT     TP_BOOST_OFF
    SUB.B   #BOOST_EXTRA,FUEL

    SUB.B   #1,         BOOST_TIMER
    BNE     TP_FLARE_STATE

TP_BOOST_OFF:
    CLR.B   BOOST_ACTIVE
    CLR.B   BOOST_TIMER

    ; --- 3. Solar Flare state machine ---
TP_FLARE_STATE:

    ; Priority 1: active flare is running
    TST.B   FLARE_ACTIVE
    BEQ     TP_CHECK_WARNING

    SUB.B   #1,         FLARE_TIMER
    BNE     TP_DONE                 ; Still counting down
    CLR.B   FLARE_ACTIVE            ; Flare over
    MOVE.B  #FLARE_COOL_TICKS,FLARE_COOLDOWN ; Start cooldown
    BRA     TP_DONE

    ; Priority 2: warning phase is running
TP_CHECK_WARNING:
    TST.B   FLARE_WARNING
    BEQ     TP_CHECK_COOLDOWN

    ; Toggle the flash flag every warning tick for border flash
    MOVE.B  WARN_FLASH, D1
    EOR.B   #1,         D1
    MOVE.B  D1,         WARN_FLASH

    SUB.B   #1,         FLARE_WARN_TIMER
    BNE     TP_DONE                 ; Warning still counting down

    ; Warning expired: promote to active flare
    CLR.B   FLARE_WARNING
    CLR.B   WARN_FLASH              ; Stop flash, border goes solid
    MOVE.B  #1,         FLARE_ACTIVE
    MOVE.B  #FLARE_TICKS,FLARE_TIMER
    BRA     TP_DONE

    ; Priority 3: cooldown is running (block new flares)
TP_CHECK_COOLDOWN:
    TST.B   FLARE_COOLDOWN
    BEQ     TP_IDLE                 ; Cooldown over: allow new flare

    SUB.B   #1,         FLARE_COOLDOWN ; Tick down cooldown
    BRA     TP_DONE

    ; Priority 4: idle - roll for new flare
TP_IDLE:
    JSR     RANNUM                  ; Returns 0-31 in D2
    TST.B   D2
    BNE     TP_DONE                 ; Non-zero: no flare this tick

    ; Start the warning phase
    MOVE.B  #1,         FLARE_WARNING
    MOVE.B  #FLARE_WARN_TICKS,FLARE_WARN_TIMER
    CLR.B   WARN_FLASH              ; Start flash from 0

TP_DONE:
    RTS

*-----------------------------------------------------------
* Subroutine    : Dynamic Delay
* Description   : Halves loop count during boost for speed burst.
*-----------------------------------------------------------

DYNAMIC_DELAY:
    MOVEM.L D0,         -(SP)
    MOVE.L  DELAY_COUNT,D0

    TST.B   BOOST_ACTIVE
    BEQ     DD_LOOP
    LSR.L   #1,         D0

DD_LOOP:
    NOP
    SUB.L   #1,         D0
    BNE     DD_LOOP
    MOVEM.L (SP)+,      D0
    RTS

*-----------------------------------------------------------
* Subroutine    : Draw
*-----------------------------------------------------------

DRAW:
    MOVE.B  #94,        D0
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$FF00,     D1
    TRAP    #15

    BSR     DRAW_BORDER
    BSR     DRAW_HUD
    BSR     DRAW_BODY
    BSR     DRAW_FOOD_CELL
    BSR     DRAW_SNAKE_HEAD
    RTS

*-----------------------------------------------------------
* Subroutine    : Draw Border
* Description   : Border colour reflects the flare state machine:
*
*   IDLE / COOLDOWN  : DARKGREEN  (normal)
*   FLARE_WARNING    : alternates YELLOW / DARKGREEN each tick
*                      using WARN_FLASH toggle to create a visible
*                      flashing alert before controls are reversed
*   FLARE_ACTIVE     : solid YELLOW
*-----------------------------------------------------------

DRAW_BORDER:
    ; Determine border colour for this frame
    TST.B   FLARE_ACTIVE
    BNE     DB_SOLID_YELLOW         ; Active flare: solid yellow

    TST.B   FLARE_WARNING
    BEQ     DB_NORMAL               ; No warning: normal green

    ; Warning phase: flash based on WARN_FLASH toggle
    TST.B   WARN_FLASH
    BEQ     DB_NORMAL               ; Toggle=0: show green this frame
    BRA     DB_SOLID_YELLOW         ; Toggle=1: show yellow this frame

DB_NORMAL:
    MOVE.L  #DARKGREEN, D1
    BRA     DB_SET_COLOR

DB_SOLID_YELLOW:
    MOVE.L  #YELLOW,    D1

DB_SET_COLOR:
    MOVE.W  #81,        D0
    TRAP    #15

    MOVE.W  #0,         D1          ; Top bar
    MOVE.W  #0,         D2
    MOVE.W  #SCREEN_PX, D3
    MOVE.W  #3,         D4
    MOVE.W  #87,        D0
    TRAP    #15

    MOVE.W  #0,         D1          ; Bottom bar
    MOVE.W  #637,       D2
    MOVE.W  #SCREEN_PX, D3
    MOVE.W  #SCREEN_PX, D4
    MOVE.W  #87,        D0
    TRAP    #15

    MOVE.W  #0,         D1          ; Left bar
    MOVE.W  #0,         D2
    MOVE.W  #3,         D3
    MOVE.W  #SCREEN_PX, D4
    MOVE.W  #87,        D0
    TRAP    #15

    MOVE.W  #637,       D1          ; Right bar
    MOVE.W  #0,         D2
    MOVE.W  #SCREEN_PX, D3
    MOVE.W  #SCREEN_PX, D4
    MOVE.W  #87,        D0
    TRAP    #15
    RTS

*-----------------------------------------------------------
* Subroutine    : Draw HUD
* Description   : Text overlay. Flare warning, active flare
*                 and boost messages are each conditional.
*-----------------------------------------------------------

DRAW_HUD:
    CLR.L   D1

    ; Score
    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$0201,     D1
    TRAP    #15
    LEA     SCORE_MSG,  A1
    MOVE    #13,        D0
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$0901,     D1
    TRAP    #15
    MOVE.B  #03,        D0
    MOVE.L  PLAYER_SCORE,D1
    TRAP    #15

    ; Controls reminder
    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$2001,     D1
    TRAP    #15
    LEA     CTRL_MSG,   A1
    MOVE    #13,        D0
    TRAP    #15

    ; X position
    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$0202,     D1
    TRAP    #15
    LEA     X_MSG,      A1
    MOVE    #13,        D0
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$0502,     D1
    TRAP    #15
    MOVE.B  #03,        D0
    CLR.L   D1
    MOVE.B  SNAKE_X,    D1
    TRAP    #15

    ; Y position
    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$1002,     D1
    TRAP    #15
    LEA     Y_MSG,      A1
    MOVE    #13,        D0
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$1302,     D1
    TRAP    #15
    MOVE.B  #03,        D0
    CLR.L   D1
    MOVE.B  SNAKE_Y,    D1
    TRAP    #15

    ; Snake length
    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$0203,     D1
    TRAP    #15
    LEA     LEN_MSG,    A1
    MOVE    #13,        D0
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$0803,     D1
    TRAP    #15
    MOVE.B  #03,        D0
    CLR.L   D1
    MOVE.B  SNAKE_LEN,  D1
    TRAP    #15

    ; Fuel
    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$0204,     D1
    TRAP    #15
    LEA     FUEL_MSG,   A1
    MOVE    #13,        D0
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$0904,     D1
    TRAP    #15
    MOVE.B  #03,        D0
    CLR.L   D1
    MOVE.B  FUEL,       D1
    TRAP    #15

    ; Shield
    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$0205,     D1
    TRAP    #15
    LEA     SHLD_MSG,   A1
    MOVE    #13,        D0
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$0905,     D1
    TRAP    #15
    MOVE.B  #03,        D0
    CLR.L   D1
    MOVE.B  SHIELD,     D1
    TRAP    #15

    ; Solar Flare INCOMING warning (during warning phase only)
    TST.B   FLARE_WARNING
    BEQ     HUD_NO_WARNING
    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$2004,     D1          ; Col 32, Row 4
    TRAP    #15
    LEA     FLARE_WARN_MSG,A1
    MOVE    #13,        D0
    TRAP    #15

HUD_NO_WARNING:
    ; Solar Flare ACTIVE message (during active phase only)
    TST.B   FLARE_ACTIVE
    BEQ     HUD_NO_FLARE
    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$2004,     D1          ; Same row, replaces warning text
    TRAP    #15
    LEA     FLARE_MSG,  A1
    MOVE    #13,        D0
    TRAP    #15

HUD_NO_FLARE:
    ; Boost active indicator
    TST.B   BOOST_ACTIVE
    BEQ     HUD_NO_BOOST
    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$2005,     D1          ; Col 32, Row 5
    TRAP    #15
    LEA     BOOST_MSG,  A1
    MOVE    #13,        D0
    TRAP    #15

HUD_NO_BOOST:
    RTS

*-----------------------------------------------------------
* Subroutine    : Draw Body
*-----------------------------------------------------------

DRAW_BODY:
    MOVEM.L D0-D7/A0,   -(SP)

    CLR.L   D5
    MOVE.B  SNAKE_LEN,  D5
    CMP.B   #2,         D5
    BLT     DRAW_BODY_DONE

    MOVE.W  #81,        D0
    MOVE.L  #SNAKEGREEN,D1
    TRAP    #15

    MOVE.B  #1,         D6

DRAW_BODY_LOOP:
    CLR.L   D7
    MOVE.B  D6,         D7

    LEA     BODY_X,     A0
    ADDA.W  D7,         A0
    CLR.L   D1
    MOVE.B  (A0),       D1

    LEA     BODY_Y,     A0
    ADDA.W  D7,         A0
    CLR.L   D2
    MOVE.B  (A0),       D2

    BSR     DRAW_CELL

    ADD.B   #1,         D6
    CMP.B   D5,         D6
    BLT     DRAW_BODY_LOOP

DRAW_BODY_DONE:
    MOVEM.L (SP)+,      D0-D7/A0
    RTS

*-----------------------------------------------------------
* Subroutine    : Draw Food Cell
*-----------------------------------------------------------

DRAW_FOOD_CELL:
    MOVE.W  #81,        D0
    MOVE.L  #RED,       D1
    TRAP    #15
    CLR.L   D1
    CLR.L   D2
    MOVE.B  FOOD_X,     D1
    MOVE.B  FOOD_Y,     D2
    BSR     DRAW_CELL
    RTS

*-----------------------------------------------------------
* Subroutine    : Draw Snake Head
*-----------------------------------------------------------

DRAW_SNAKE_HEAD:
    MOVE.W  #81,        D0
    MOVE.L  #WHITE,     D1
    TRAP    #15
    CLR.L   D1
    CLR.L   D2
    MOVE.B  SNAKE_X,    D1
    MOVE.B  SNAKE_Y,    D2
    BSR     DRAW_CELL
    RTS

*-----------------------------------------------------------
* Subroutine    : Draw Cell
* Description   : 20x20 pixel filled rectangle at grid (D1, D2).
*                 Caller sets fill colour before calling.
*-----------------------------------------------------------

DRAW_CELL:
    MULU    #CELL_SIZE, D1
    MULU    #CELL_SIZE, D2
    MOVE.W  D1,         D3
    MOVE.W  D2,         D4
    ADD.W   #CELL_SIZE, D3
    ADD.W   #CELL_SIZE, D4
    MOVE.W  #87,        D0
    TRAP    #15
    RTS

*-----------------------------------------------------------
* Subroutine    : Dead
*-----------------------------------------------------------

DEAD:
    BSR     PLAY_OPPS

    MOVE.W  #3,         D7

DEAD_FLASH:
    MOVE.W  #81,        D0
    MOVE.L  #RED,       D1
    TRAP    #15
    JSR     SCREENFLASH
    JSR     DELAY

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$FF00,     D1
    TRAP    #15
    JSR     DELAY

    DBRA    D7,         DEAD_FLASH

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$0D0D,     D1
    TRAP    #15
    LEA     DEAD_MSG,   A1
    MOVE    #13,        D0
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$0D0E,     D1
    TRAP    #15
    LEA     SCORE_MSG,  A1
    MOVE    #13,        D0
    TRAP    #15

    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$160E,     D1
    TRAP    #15
    MOVE.B  #03,        D0
    MOVE.L  PLAYER_SCORE,D1
    TRAP    #15

    SIMHALT

*-----------------------------------------------------------
* Subroutine    : Exit
*-----------------------------------------------------------

EXIT:
    MOVE.B  #TC_CURSR_P,D0
    MOVE.W  #$0D0D,     D1
    TRAP    #15
    LEA     EXIT_MSG,   A1
    MOVE    #13,        D0
    TRAP    #15
    MOVE.B  #TC_EXIT,   D0
    TRAP    #15
    SIMHALT

*-----------------------------------------------------------
* Subroutines   : Sound
*-----------------------------------------------------------

OPPS_LOAD:
    LEA     OPPS_WAV,   A1
    MOVE    #OPPS_INDEX,D1
    MOVE    #71,        D0
    TRAP    #15
    RTS

PLAY_OPPS:
    MOVE    #OPPS_INDEX,D1
    MOVE    #72,        D0
    TRAP    #15
    RTS

*-----------------------------------------------------------
* Subroutine    : Set Screen
*-----------------------------------------------------------

SETSCREEN:
    MOVEM   D0-D1,      -(SP)
    MOVE.W  #33,        D0
    MOVE.W  #640,       D1
    SWAP    D1
    MOVE.W  #640,       D1
    TRAP    #15
    MOVEM   (SP)+,      D0-D1
    RTS

*-----------------------------------------------------------
* Subroutine    : Screen Flash
*-----------------------------------------------------------

SCREENFLASH:
    MOVEM   D0-D4,      -(SP)
    MOVE.W  #87,        D0
    MOVE.W  #0,         D1
    MOVE.W  #0,         D2
    MOVE.W  #SCREEN_PX, D3
    MOVE.W  #SCREEN_PX, D4
    TRAP    #15
    MOVEM   (SP)+,      D0-D4
    RTS

*-----------------------------------------------------------
* Subroutine    : Delay
*-----------------------------------------------------------

DELAY:
    MOVEM.L D0,         -(SP)
    MOVE.L  DELAY_COUNT,D0
DLOOP:
    NOP
    SUB.L   #1,         D0
    BNE     DLOOP
    MOVEM.L (SP)+,      D0
    RTS

*-----------------------------------------------------------
* Subroutine    : Place Food
*-----------------------------------------------------------

PLACEFOOD:
    JSR     RANNUM
    MOVE.B  D2,         FOOD_X
    JSR     RANNUM
    MOVE.B  D2,         FOOD_Y
    RTS

*-----------------------------------------------------------
* Subroutine    : Random Number
* Description   : Returns 0-31 in D2. CLR.L D2 before byte
*                 move prevents DIVU overflow (food spawn fix).
*-----------------------------------------------------------

RANNUM:
    MOVEM   D0-D1,      -(SP)
    MOVE.W  #8,         D0
    TRAP    #15
    CLR.L   D2
    MOVE.B  D1,         D2
    MOVE.L  D2,         D1
    DIVU    #8,         D1
    MOVE.W  D1,         D2
    MOVEM   (SP)+,      D0-D1
    RTS

*-----------------------------------------------------------
* Section       : Messages
*-----------------------------------------------------------

DIFF_TITLE_MSG  DC.B    '=== SNAKE GAME ===',0
DIFF_SEL_MSG    DC.B    'Select Difficulty :',0
DIFF_EASY_MSG   DC.B    '1 = Easy    [ 3 Shields | Full Fuel | Slow  ]',0
DIFF_MED_MSG    DC.B    '2 = Medium  [ 2 Shields | 75% Fuel  | Med   ]',0
DIFF_HARD_MSG   DC.B    '3 = Hard    [ 1 Shield  | 50% Fuel  | Fast  ]',0
DIFF_PRMPT_MSG  DC.B    'Press 1, 2 or 3 to begin...',0

TITLE_MSG       DC.B    '*** SNAKE GAME ***',0
CTRL_MSG        DC.B    'Arrows:Move  Space:Boost  Q:Quit',0
BOOST_TIP_MSG   DC.B    'Space = Boost toggle (costs Fuel)',0
QUIT_MSG        DC.B    'Q : Quit',0

SCORE_MSG       DC.B    'Score : ',0
X_MSG           DC.B    'X:',0
Y_MSG           DC.B    'Y:',0
LEN_MSG         DC.B    'Len : ',0
FUEL_MSG        DC.B    'Fuel  : ',0
SHLD_MSG        DC.B    'Shld  : ',0
FLARE_WARN_MSG  DC.B    '! SOLAR FLARE INCOMING !',0
FLARE_MSG       DC.B    '! SOLAR FLARE - Controls Reversed !',0
BOOST_MSG       DC.B    '>> BOOST ACTIVE <<',0
DEAD_MSG        DC.B    '*** GAME OVER ***',0
EXIT_MSG        DC.B    'Exiting....',0

*-----------------------------------------------------------
* Section       : Sound Files
*-----------------------------------------------------------

OPPS_WAV        DC.B    'opps.wav',0

*-----------------------------------------------------------
* Section       : Game Data
*-----------------------------------------------------------

PLAYER_SCORE    DS.L    1           ; Player score
SNAKE_X         DS.B    1           ; Head column      (0-31)
SNAKE_Y         DS.B    1           ; Head row         (0-31)
SNAKE_DIR       DS.B    1           ; Direction        (1=L 2=U 3=R 4=D)
SNAKE_LEN       DS.B    1           ; Length           (1-30)
FOOD_X          DS.B    1           ; Food column      (0-31)
FOOD_Y          DS.B    1           ; Food row         (0-31)
DELAY_COUNT     DS.L    1           ; Speed delay count
DIFFICULTY      DS.B    1           ; Chosen difficulty (1/2/3)
FUEL            DS.B    1           ; Fuel              (0-100)
FUEL_TICK       DS.B    1           ; Half-rate toggle  (0/1)
SHIELD          DS.B    1           ; Shields           (0-3)
FLARE_ACTIVE    DS.B    1           ; Flare active flag (0/1)
FLARE_TIMER     DS.B    1           ; Active flare ticks remaining
FLARE_WARNING   DS.B    1           ; Warning phase flag (0/1)
FLARE_WARN_TIMER DS.B   1           ; Warning ticks remaining
FLARE_COOLDOWN  DS.B    1           ; Cooldown ticks remaining
WARN_FLASH      DS.B    1           ; Border flash toggle (0/1)
BOOST_ACTIVE    DS.B    1           ; Boost flag        (0/1)
BOOST_TIMER     DS.B    1           ; Boost ticks remaining
BODY_X          DS.B    30          ; Body column array [0]=head
BODY_Y          DS.B    30          ; Body row array    [0]=head

    END     START

*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~4~
