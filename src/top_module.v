`default_nettype none

module tt_um_vga_example(
  input  wire [7:0] ui_in,    // Dedicated inputs for player controls
  output wire [7:0] uo_out,   // Dedicated outputs
  input  wire [7:0] uio_in,   // IOs: Input path
  output wire [7:0] uio_out,  // IOs: Output path
  output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
  input  wire       ena,      // Always 1 when the design is powered, so you can ignore it
  input  wire       clk,      // Clock
  input  wire       rst_n     // Reset_n - low to reset
);

// State Definitions using localparam
localparam [1:0] 
  PLAYING   = 2'b00,
  GAME_WON  = 2'b01,
  GAME_OVER = 2'b10;

// Declare state registers
reg [1:0] current_state, next_state;

// Declare game variables
reg [9:0] score;             // Score is 10 bits to hold values up to 1023
reg game_won_flag;           // Flag to indicate game won
reg game_over_flag;          // Flag to indicate game over

// VGA signals
wire hsync;
wire vsync;
wire [1:0] R;
wire [1:0] G;
wire [1:0] B;
wire video_active;
wire [9:0] pix_x;
wire [9:0] pix_y;

// TinyVGA PMOD
assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

// Unused outputs assigned to 0
assign uio_out = 0;
assign uio_oe  = 0;

// Suppress unused signals warning
wire _unused_ok = &{ena, uio_in};

// Player control signals
// ui_in[0]: Move right
// ui_in[1]: Move left
// ui_in[2]: Fire
// ui_in[3]: Reset game

// Define screen and shooter dimensions
localparam SCREEN_WIDTH    = 640;  // VGA standard width
localparam SHOOTER_WIDTH    = 12;  // Shooter sprite actual width based on drawing logic
localparam SHOOTER_MIN_X    = 0;    // Minimum x position
localparam SHOOTER_MAX_X    = SCREEN_WIDTH - SHOOTER_WIDTH - 1; // 640 - 12 -1 = 627

// Alien movement parameters
reg [9:0] alien_offset_x;  // Horizontal offset for alien movement
reg [9:0] alien_offset_y;  // Vertical offset for alien movement
reg alien_direction;       // 1 for right, 0 for left
reg [31:0] alien_move_counter; // Slow down the alien movement

// Shooter parameters
reg [9:0] shooter_x;     // Horizontal position of the shooter
reg [9:0] bullet_x;
reg [9:0] bullet_y;
reg bullet_active;

// Alien health: each alien starts with 1 health point
localparam NUM_ROWS = 5;
localparam NUM_COLUMNS = 11;
reg alien_health [0:NUM_ROWS-1][0:NUM_COLUMNS-1];  // 1-bit wide

// Integers for loop counters
integer i, j;
integer row, col;

// Declare a counter for remaining aliens
reg [6:0] aliens_remaining; // Enough bits to count up to 55 (NUM_ROWS * NUM_COLUMNS)

// Player health: starts at 3
reg [1:0] player_health; // 2-bit to hold values up to 3
reg [3:0] digit_health;
localparam HEALTH_DIGIT_X = 450; // Position for health digit
localparam HEALTH_DIGIT_Y = 20;  // Same Y position as score digits

// VGA signal generation
hvsync_generator hvsync_gen(
  .clk(clk),
  .reset(~rst_n),
  .hsync(hsync),
  .vsync(vsync),
  .display_on(video_active),
  .hpos(pix_x),
  .vpos(pix_y)
);

// Alien sprite definitions
// Small Alien (Top Row)
reg [7:0] small_alien_sprite [0:7];
initial begin
  small_alien_sprite[0] = 8'b00011000;
  small_alien_sprite[1] = 8'b00111100;
  small_alien_sprite[2] = 8'b01111110;
  small_alien_sprite[3] = 8'b11011011;
  small_alien_sprite[4] = 8'b11111111;
  small_alien_sprite[5] = 8'b00100100;
  small_alien_sprite[6] = 8'b01000010;
  small_alien_sprite[7] = 8'b10000001;
end

// Distinct Alien Shape (2nd and 3rd Rows)
reg [11:0] distinct_alien_sprite [0:11];
initial begin
  distinct_alien_sprite[0]  = 12'b000011100000;
  distinct_alien_sprite[1]  = 12'b000111110000;
  distinct_alien_sprite[2]  = 12'b001111111000;
  distinct_alien_sprite[3]  = 12'b011011101100;
  distinct_alien_sprite[4]  = 12'b111111111110;
  distinct_alien_sprite[5]  = 12'b101111111010;
  distinct_alien_sprite[6]  = 12'b101001100010;
  distinct_alien_sprite[7]  = 12'b101000000010;
  distinct_alien_sprite[8]  = 12'b001100110000;
  distinct_alien_sprite[9]  = 12'b010000001000;
  distinct_alien_sprite[10] = 12'b100000000100;
  distinct_alien_sprite[11] = 12'b000000000000;
end

// Smaller Large Alien (4th and 5th Rows)
reg [9:0] small_large_alien_sprite [0:9];
initial begin
  small_large_alien_sprite[0] = 10'b0011111100;
  small_large_alien_sprite[1] = 10'b0111111110;
  small_large_alien_sprite[2] = 10'b1101101101;
  small_large_alien_sprite[3] = 10'b1111111111;
  small_large_alien_sprite[4] = 10'b0111111110;
  small_large_alien_sprite[5] = 10'b0010010010;
  small_large_alien_sprite[6] = 10'b0100000100;
  small_large_alien_sprite[7] = 10'b1000000010;
  small_large_alien_sprite[8] = 10'b1100000110;
  small_large_alien_sprite[9] = 10'b0111111110;
end

// 7-segment display font for digits 0-9
reg [6:0] digit_segments [0:9];
reg [3:0] digit0, digit1, digit2;
initial begin
  digit_segments[0] = 7'b0111111;  // 0
  digit_segments[1] = 7'b0000110;  // 1
  digit_segments[2] = 7'b1011011;  // 2
  digit_segments[3] = 7'b1001111;  // 3
  digit_segments[4] = 7'b1100110;  // 4
  digit_segments[5] = 7'b1101101;  // 5
  digit_segments[6] = 7'b1111101;  // 6
  digit_segments[7] = 7'b0000111;  // 7
  digit_segments[8] = 7'b1111111;  // 8
  digit_segments[9] = 7'b1101111;  // 9
end

// 16x16 Heart sprite
reg [15:0] heart_sprite [0:15];
initial begin
  heart_sprite[0]  = 16'b0000000000000000;
  heart_sprite[1]  = 16'b0000000000000000;
  heart_sprite[2]  = 16'b0001110001110000;
  heart_sprite[3]  = 16'b0011111011111000;
  heart_sprite[4]  = 16'b0011111111111000;
  heart_sprite[5]  = 16'b0011111111111000;
  heart_sprite[6]  = 16'b0001111111110000;
  heart_sprite[7]  = 16'b0000111111100000;
  heart_sprite[8]  = 16'b0000011111000000;
  heart_sprite[9]  = 16'b0000001110000000;
  heart_sprite[10] = 16'b0000000100000000;
  heart_sprite[11] = 16'b0000000000000000;
  heart_sprite[12] = 16'b0000000000000000;
  heart_sprite[13] = 16'b0000000000000000;
  heart_sprite[14] = 16'b0000000000000000;
  heart_sprite[15] = 16'b0000000000000000;
end

// 16x16 Trophy Sprite Definition
reg [15:0] trophy_sprite [0:15];
initial begin
  trophy_sprite[0]  = 16'b0000000000000000;
  trophy_sprite[1]  = 16'b0000000000000000;
  trophy_sprite[2]  = 16'b0000000000000000;
  trophy_sprite[3]  = 16'b0000000000000000;
  trophy_sprite[4]  = 16'b0000000000000000;
  trophy_sprite[5]  = 16'b0000000000000000;
  trophy_sprite[6]  = 16'b0011111111111100;
  trophy_sprite[7]  = 16'b0011111111111100;
  trophy_sprite[8]  = 16'b0011111111111100;
  trophy_sprite[9]  = 16'b0011111111111100;
  trophy_sprite[10] = 16'b0011111111111100;
  trophy_sprite[11] = 16'b0001111111111000;
  trophy_sprite[12] = 16'b0000011111100000;
  trophy_sprite[13] = 16'b0000011111100000;
  trophy_sprite[14] = 16'b0000011111100000;
  trophy_sprite[15] = 16'b0000111111110000;
end

// Position Parameters
localparam TROPHY_WIDTH = 16;
localparam TROPHY_HEIGHT = 16;

// Positioning the trophy to the left of the scoreboard
localparam DIGIT_WIDTH = 10;
localparam DIGIT_HEIGHT = 14;
localparam DIGIT2_X = 30;  // Hundreds place
localparam DIGIT1_X = 60;  // Tens place
localparam DIGIT0_X = 90;  // Ones place
localparam DIGIT_Y = 20;   // Y position for all digits
localparam TROPHY_X = DIGIT2_X - TROPHY_WIDTH - 12; // 12 pixels padding
localparam TROPHY_Y = DIGIT_Y - 3;               // Align Y position with scoreboard

localparam HEART_X = DIGIT2_X + 394;  // Position of the heart to the left of the score
localparam HEART_Y = DIGIT_Y + 1;     // Same Y position as the score

// Alien grid parameters
localparam ALIEN_WIDTH = 24;    // Alien width
localparam ALIEN_HEIGHT = 24;   // Alien height
localparam ALIEN_SPACING_X = 6; // Space between aliens horizontally
localparam ALIEN_SPACING_Y = 8; // Space between aliens vertically

// Bullet dimensions
localparam BULLET_WIDTH = 4;
localparam BULLET_HEIGHT = 8;

// ----- Barrier Definitions Start -----
// Define barrier parameters
localparam BARRIER_WIDTH = 60;
localparam BARRIER_HEIGHT = 30;

// Define barrier X positions individually
localparam [9:0] barrier_x0 = 80;
localparam [9:0] barrier_x1 = 200;
localparam [9:0] barrier_x2 = 320;
localparam [9:0] barrier_x3 = 440;
localparam [9:0] barrier_y = 400;

// Declare barrier hitpoints
reg [3:0] barrier_hitpoints [0:3]; // 4 barriers, each with 4 bits (0-15)

// Barrier pixel signal
reg barrier_pixel;
// ----- Barrier Definitions End -----

// Initialize variables
initial begin
  shooter_x = 253;
  bullet_x = 0;
  bullet_y = 0;
  bullet_active = 0;
  movement_counter = 0;
  bullet_move_counter = 0;
  score = 0;
  game_won_flag = 0;
  game_over_flag = 0;
  player_health = 2'b11;
  aliens_remaining = NUM_ROWS * NUM_COLUMNS;

  alien_offset_x = 0;
  alien_offset_y = 0;
  alien_direction = 1;
  alien_move_counter = 0;

  // Initialize alien health to 1 for each alien
  for (i = 0; i < NUM_ROWS; i = i + 1) begin
    for (j = 0; j < NUM_COLUMNS; j = j + 1) begin
      alien_health[i][j] = 1'b1;  // Set to 1 health point
    end
  end

  // Initialize barrier hitpoints
  barrier_hitpoints[0] = 4'd10;
  barrier_hitpoints[1] = 4'd10;
  barrier_hitpoints[2] = 4'd10;
  barrier_hitpoints[3] = 4'd10;
end

// Counter for alien shooting
reg [31:0] alien_shoot_counter;

// Simple random number generator using LFSR
reg [15:0] lfsr;
wire lfsr_feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];

always @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    lfsr <= 16'hACE1; // Seed value
  else
    lfsr <= {lfsr[14:0], lfsr_feedback};
end

// Alien movement and shooting logic
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    // Reset alien movement variables
    alien_offset_x <= 0;
    alien_offset_y <= 0;
    alien_direction <= 1;
    alien_move_counter <= 0;
    alien_shoot_counter <= 0;

    // Reset barrier hitpoints
    barrier_hitpoints[0] <= 4'd10;
    barrier_hitpoints[1] <= 4'd10;
    barrier_hitpoints[2] <= 4'd10;
    barrier_hitpoints[3] <= 4'd10;
  end else if (ui_in[3]) begin
    // Reset alien movement variables
    alien_offset_x <= 0;
    alien_offset_y <= 0;
    alien_direction <= 1;
    alien_move_counter <= 0;
    alien_shoot_counter <= 0;

    // Reset barrier hitpoints
    barrier_hitpoints[0] <= 4'd10;
    barrier_hitpoints[1] <= 4'd10;
    barrier_hitpoints[2] <= 4'd10;
    barrier_hitpoints[3] <= 4'd10;
  end else if (current_state == PLAYING) begin
    // Increment the move counter to slow down alien movement updates
    alien_move_counter <= alien_move_counter + 1;
    alien_shoot_counter <= alien_shoot_counter + 1;

    // Move the aliens when the counter reaches the threshold
    if (alien_move_counter >= 50000) begin  // Adjust this value to control the speed of movement
      alien_move_counter <= 0; // Reset the counter when it reaches the threshold

      // Update alien position based on direction
      if (alien_direction) begin
        if (alien_offset_x < 100) begin
          alien_offset_x <= alien_offset_x + 1; // Move to the right
        end else begin
          alien_direction <= 0; // Change direction to left
        end
      end else begin
        if (alien_offset_x > 0) begin
          alien_offset_x <= alien_offset_x - 1; // Move to the left
        end else begin
          alien_direction <= 1; // Change direction to right
        end
      end
    end
  end else begin
    // In GAME_WON or GAME_OVER states, stop alien movements
    alien_move_counter <= 0;
    alien_shoot_counter <= 0;
  end
end

// Alien drawing logic with movement
reg alien_pixel;
reg [2:0] alien_color;
reg [9:0] alien_x, alien_y;
reg [9:0] sprite_x, sprite_y;

always @* begin
  // Default assignments
  alien_pixel = 0;
  alien_color = 3'b000;
  alien_x = 0;
  alien_y = 0;
  sprite_x = 0;
  sprite_y = 0;

  // Loop over each row and column of aliens
  if (current_state == PLAYING) begin
    for (row = 0; row < NUM_ROWS; row = row + 1) begin
      for (col = 0; col < NUM_COLUMNS; col = col + 1) begin
        // Check if the alien is alive
        if (alien_health[row][col]) begin 
          // Calculate the top-left position of each alien with movement offsets
          alien_x = col * (ALIEN_WIDTH + ALIEN_SPACING_X) + 70 + alien_offset_x;
          alien_y = row * (ALIEN_HEIGHT + ALIEN_SPACING_Y) + 150 + alien_offset_y;

          // Set alien sprite dimensions based on the row
          if (row == 0) begin
            sprite_x = (pix_x - alien_x) / 2;  // Smaller sprite (8x8 pixels)
            sprite_y = (pix_y - alien_y) / 2;
            if (pix_x >= alien_x && pix_x < alien_x + 16 &&
                pix_y >= alien_y && pix_y < alien_y + 16 &&
                sprite_x < 8 && sprite_y < 8 &&
                small_alien_sprite[sprite_y][sprite_x]) begin
              alien_pixel = 1;
              alien_color = 3'b011;  // Bright white color for small aliens
            end
          end else if (row == 1 || row == 2) begin
            sprite_x = (pix_x - alien_x) / 2;  // Medium sprite (12x12 pixels)
            sprite_y = (pix_y - alien_y) / 2;
            if (pix_x >= alien_x && pix_x < alien_x + 24 &&
                pix_y >= alien_y && pix_y < alien_y + 24 &&
                sprite_x < 12 && sprite_y < 12 &&
                distinct_alien_sprite[sprite_y][sprite_x]) begin
              alien_pixel = 1;
              alien_color = 3'b101;  // Bright white color for distinct aliens
            end
          end else if (row == 3 || row == 4) begin
            sprite_x = (pix_x - alien_x) / 2;  // Smaller large sprite (10x10 pixels)
            sprite_y = (pix_y - alien_y) / 2;
            if (pix_x >= alien_x && pix_x < alien_x + 20 &&
                pix_y >= alien_y && pix_y < alien_y + 20 &&
                sprite_x < 10 && sprite_y < 10 &&
                small_large_alien_sprite[sprite_y][sprite_x]) begin
              alien_pixel = 1;
              alien_color = 3'b110;  // Bright white color for smaller large aliens
            end
          end
        end
      end
    end
  end
end

reg collision_occurred;

// ----- Movement Direction Tracking Start -----
// Define movement direction states
localparam [1:0] 
  DIR_IDLE  = 2'b00,
  DIR_LEFT  = 2'b01,
  DIR_RIGHT = 2'b10;

// Register to track current movement direction
reg [1:0] movement_dir;

// Registers to hold previous button states for edge detection
reg prev_button0, prev_button1;

// Edge detection for movement buttons
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    prev_button0 <= 0;
    prev_button1 <= 0;
    movement_dir <= DIR_IDLE;
  end else begin
    // Update previous button states
    prev_button0 <= ui_in[0];
    prev_button1 <= ui_in[1];

    // Detect rising edge for button 0 (Move Right)
    if (ui_in[0] && !prev_button0) begin
      movement_dir <= DIR_RIGHT;
    end 
    // Detect rising edge for button 1 (Move Left)
    else if (ui_in[1] && !prev_button1) begin
      movement_dir <= DIR_LEFT;
    end 
    // If neither button is pressed, set to IDLE
    else if (!ui_in[0] && !ui_in[1]) begin
      movement_dir <= DIR_IDLE;
    end
    // If both buttons are pressed, prioritize the last pressed button
    // Since rising edges are handled above, movement_dir already reflects the latest press
  end
end
// ----- Movement Direction Tracking End -----

// Shooter logic, bullet control, collision detection, and scoring with state machine integration
reg [19:0] movement_counter;      // Counter to control the speed of player movement
reg [19:0] bullet_move_counter;   // Counter to control bullet movement speed
reg prev_fire_button;             // Register to hold previous state of fire button

// Edge detection for fire button
always @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    prev_fire_button <= 0;
  else
    prev_fire_button <= ui_in[2];
end

wire fire_button_rising_edge = ui_in[2] && !prev_fire_button;

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    // Reset shooter and bullet variables
    shooter_x <= 253;
    bullet_x <= 0;
    bullet_y <= 0;
    bullet_active <= 0;
    movement_counter <= 0;
    bullet_move_counter <= 0; // Reset bullet movement counter
    // Reset score and game state flags
    score <= 0;
    game_won_flag <= 0;
    game_over_flag <= 0;
    player_health <= 2'b11;
    aliens_remaining <= NUM_ROWS * NUM_COLUMNS;
    // Reset alien health
    for (i = 0; i < NUM_ROWS; i = i + 1) begin
      for (j = 0; j < NUM_COLUMNS; j = j + 1) begin
        alien_health[i][j] <= 1'b1;  // Set to 1 health point
      end
    end

    alien_offset_x <= 0;
    alien_offset_y <= 0;
    alien_direction <= 1;
    alien_move_counter <= 0;
    prev_fire_button <= 0;  // Reset prev_fire_button
    collision_occurred <= 0;

    // Reset barrier hitpoints
    barrier_hitpoints[0] <= 4'd10;
    barrier_hitpoints[1] <= 4'd10;
    barrier_hitpoints[2] <= 4'd10;
    barrier_hitpoints[3] <= 4'd10;
  end else if (ui_in[3] || game_over_flag || game_won_flag) begin
    // Reset shooter and bullet variables
    shooter_x <= 253;
    bullet_x <= 0;
    bullet_y <= 0;
    bullet_active <= 0;
    movement_counter <= 0;
    bullet_move_counter <= 0; // Reset bullet movement counter
    // Reset score and game state flags
    score <= 0;
    game_won_flag <= 0;
    game_over_flag <= 0;
    player_health <= 2'b11;
    aliens_remaining <= NUM_ROWS * NUM_COLUMNS;
    // Reset alien health
    for (i = 0; i < NUM_ROWS; i = i + 1) begin
      for (j = 0; j < NUM_COLUMNS; j = j + 1) begin
        alien_health[i][j] <= 1'b1;  // Set to 1 health point
      end
    end

    alien_offset_x <= 0;
    alien_offset_y <= 0;
    alien_direction <= 1;
    alien_move_counter <= 0;
    prev_fire_button <= 0;  // Reset prev_fire_button
    collision_occurred <= 0;

    // Reset barrier hitpoints
    barrier_hitpoints[0] <= 4'd10;
    barrier_hitpoints[1] <= 4'd10;
    barrier_hitpoints[2] <= 4'd10;
    barrier_hitpoints[3] <= 4'd10;
  end else begin
    if (current_state == PLAYING) begin
      // Initialize collision_occurred at the start of the clock cycle
      collision_occurred <= 0;

      // Bullet movement
      if (bullet_active) begin
        bullet_move_counter <= bullet_move_counter + 1;
        if (bullet_move_counter >= 3000) begin // Adjust this value to control bullet speed
          bullet_move_counter <= 0;
          if (bullet_y > 0) begin
            bullet_y <= bullet_y - 1;  // Move bullet upwards
          end else begin
            bullet_active <= 0;  // Deactivate bullet when it goes off-screen
          end
        end
      end else if (fire_button_rising_edge && !bullet_active) begin  // Fire button pressed (rising edge)
        bullet_active <= 1;
        bullet_x <= shooter_x + 4;  // Fire from the center of the shooter
        bullet_y <= 460;            // Starting bullet position
        bullet_move_counter <= 0;   // Reset counter for the new bullet
      end

      // Collision Detection and Scoring
      if (bullet_active) begin
        // Check collision with aliens
        for (row = 0; row < NUM_ROWS; row = row + 1) begin
          for (col = 0; col < NUM_COLUMNS; col = col + 1) begin
            if (alien_health[row][col] && !collision_occurred) begin
              // Calculate the alien's position
              alien_x = col * (ALIEN_WIDTH + ALIEN_SPACING_X) + 70 + alien_offset_x;
              alien_y = row * (ALIEN_HEIGHT + ALIEN_SPACING_Y) + 150 + alien_offset_y;

              // Check for collision
              if (bullet_x + BULLET_WIDTH >= alien_x && bullet_x <= alien_x + ALIEN_WIDTH &&
                  bullet_y <= alien_y + ALIEN_HEIGHT && bullet_y + BULLET_HEIGHT >= alien_y) begin  // Adjusted for bullet size

                // Alien is destroyed upon first hit
                alien_health[row][col] <= 1'b0;  // Set alien health to 0

                // Deactivate the bullet
                bullet_active <= 0;
                bullet_y <= 0;
                collision_occurred <= 1; // Prevent further collisions in this cycle

                // Decrement aliens_remaining
                aliens_remaining <= aliens_remaining - 1;

                // Increment score based on the row
                case (row)
                  0: score <= score + 30;  // 1st row = 30 points
                  1, 2: score <= score + 20;  // 2nd and 3rd row = 20 points
                  3, 4: score <= score + 10;  // 4th and 5th row = 10 points
                endcase
              end
            end
          end
        end

        // ----- Barrier Collision Detection Start -----
        if (bullet_active) begin
          // Barrier 0 Collision
          if (barrier_hitpoints[0] > 0 &&
              bullet_x + BULLET_WIDTH >= barrier_x0 &&
              bullet_x <= barrier_x0 + BARRIER_WIDTH &&
              bullet_y <= barrier_y + BARRIER_HEIGHT &&
              bullet_y + BULLET_HEIGHT >= barrier_y) begin
            barrier_hitpoints[0] <= barrier_hitpoints[0] - 1; // Reduce barrier hitpoints
            bullet_active <= 0; // Deactivate bullet
          end
          // Barrier 1 Collision
          else if (barrier_hitpoints[1] > 0 &&
                   bullet_x + BULLET_WIDTH >= barrier_x1 &&
                   bullet_x <= barrier_x1 + BARRIER_WIDTH &&
                   bullet_y <= barrier_y + BARRIER_HEIGHT &&
                   bullet_y + BULLET_HEIGHT >= barrier_y) begin
            barrier_hitpoints[1] <= barrier_hitpoints[1] - 1; // Reduce barrier hitpoints
            bullet_active <= 0; // Deactivate bullet
          end
          // Barrier 2 Collision
          else if (barrier_hitpoints[2] > 0 &&
                   bullet_x + BULLET_WIDTH >= barrier_x2 &&
                   bullet_x <= barrier_x2 + BARRIER_WIDTH &&
                   bullet_y <= barrier_y + BARRIER_HEIGHT &&
                   bullet_y + BULLET_HEIGHT >= barrier_y) begin
            barrier_hitpoints[2] <= barrier_hitpoints[2] - 1; // Reduce barrier hitpoints
            bullet_active <= 0; // Deactivate bullet
          end
          // Barrier 3 Collision
          else if (barrier_hitpoints[3] > 0 &&
                   bullet_x + BULLET_WIDTH >= barrier_x3 &&
                   bullet_x <= barrier_x3 + BARRIER_WIDTH &&
                   bullet_y <= barrier_y + BARRIER_HEIGHT &&
                   bullet_y + BULLET_HEIGHT >= barrier_y) begin
            barrier_hitpoints[3] <= barrier_hitpoints[3] - 1; // Reduce barrier hitpoints
            bullet_active <= 0; // Deactivate bullet
          end
        end
        // ----- Barrier Collision Detection End -----
      end

      // Check for game over
      if (player_health == 0 && !game_over_flag) begin
        game_over_flag <= 1;
      end

      // Check if all aliens have been destroyed
      if (aliens_remaining == 0 && !game_won_flag) begin
        game_won_flag <= 1;
      end

      // ----- Shooter Movement Logic Start -----
      // Player control logic for shooter movement using movement_dir
      if (movement_counter == 0) begin // Only update movement when the counter reaches zero
        case (movement_dir)
          DIR_LEFT: begin
            if (shooter_x > SHOOTER_MIN_X) begin
              shooter_x <= shooter_x - 10;  // Move to the left by 5 pixels
            end
          end
          DIR_RIGHT: begin
            if (shooter_x < SHOOTER_MAX_X) begin
              shooter_x <= shooter_x + 10;  // Move to the right by 5 pixels
            end
          end
          default: ; // Do nothing if DIR_IDLE
        endcase
      end
      // ----- Shooter Movement Logic End -----

      // Increment the counter to control the speed of movement
      movement_counter <= movement_counter + 1;
      if (movement_counter == 500000) begin // Adjust this value to control the speed of movement
        movement_counter <= 0; // Reset the counter when it reaches the threshold
      end
    end
  end
end

// ----- Movement Direction Tracking Start -----
// Define movement direction states

// Edge detection for movement buttons
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    prev_button0 <= 0;
    prev_button1 <= 0;
    movement_dir <= DIR_IDLE;
  end else begin
    // Update previous button states
    prev_button0 <= ui_in[0];
    prev_button1 <= ui_in[1];

    // Detect rising edge for button 0 (Move Right)
    if (ui_in[0] && !prev_button0) begin
      movement_dir <= DIR_RIGHT;
    end 
    // Detect rising edge for button 1 (Move Left)
    else if (ui_in[1] && !prev_button1) begin
      movement_dir <= DIR_LEFT;
    end 
    // If neither button is pressed, set to IDLE
    else if (!ui_in[0] && !ui_in[1]) begin
      movement_dir <= DIR_IDLE;
    end
    // If both buttons are pressed, prioritize the last pressed button
    // Since rising edges are handled above, movement_dir already reflects the latest press
  end
end
// ----- Movement Direction Tracking End -----

// ----- Bullet Rendering Start -----
wire bullet_pixel = bullet_active && 
                    (pix_x >= bullet_x && pix_x < bullet_x + BULLET_WIDTH &&
                     pix_y >= bullet_y && pix_y < bullet_y + BULLET_HEIGHT);

// Shooter drawing logic
wire shooter_pixel = (
    (pix_y >= 460 && pix_y < 462 && pix_x >= shooter_x + 6 && pix_x < shooter_x + 14) || 
    (pix_y >= 462 && pix_y < 468 && pix_x >= shooter_x + 8 && pix_x < shooter_x + 12) || 
    (pix_y >= 468 && pix_y < 470 && pix_x >= shooter_x + 4 && pix_x < shooter_x + 16)
); 

// Split the score into 3 digits (assuming the score is a maximum of 990)
always @* begin
  digit0 = score % 10;          // Least significant digit
  digit1 = (score / 10) % 10;   // Middle digit
  digit2 = (score / 100) % 10;  // Most significant digit
  digit_health = player_health; 
end

// Function to render a digit using the 7-segment display
function digit_segment;
  input [6:0] segments;
  input [9:0] x, y;    // Current pixel coordinates
  input [9:0] x0, y0;  // Top-left corner of the digit
  begin
    digit_segment = 0;
    // Segment a (top horizontal) - Bit 0
    if (segments[0] && y >= y0 && y < y0 + 2 && x >= x0 + 2 && x < x0 + 8)
      digit_segment = 1;
    // Segment b (top-right vertical) - Bit 1
    else if (segments[1] && x >= x0 + 8 && x < x0 + 10 && y >= y0 + 2 && y < y0 + 7)
      digit_segment = 1;
    // Segment c (bottom-right vertical) - Bit 2
    else if (segments[2] && x >= x0 + 8 && x < x0 + 10 && y >= y0 + 7 && y < y0 + 12)
      digit_segment = 1;
    // Segment d (bottom horizontal) - Bit 3
    else if (segments[3] && y >= y0 + 12 && y < y0 + 14 && x >= x0 + 2 && x < x0 + 8)
      digit_segment = 1;
    // Segment e (bottom-left vertical) - Bit 4
    else if (segments[4] && x >= x0 && x < x0 + 2 && y >= y0 + 7 && y < y0 + 12)
      digit_segment = 1;
    // Segment f (top-left vertical) - Bit 5
    else if (segments[5] && x >= x0 && x < x0 + 2 && y >= y0 + 2 && y < y0 + 7)
      digit_segment = 1;
    // Segment g (middle horizontal) - Bit 6
    else if (segments[6] && y >= y0 + 7 && y < y0 + 9 && x >= x0 + 2 && x < x0 + 8)
      digit_segment = 1;
  end
endfunction

reg heart_pixel;
integer heart_sprite_x, heart_sprite_y;
reg trophy_pixel; 
integer trophy_sprite_x, trophy_sprite_y;

always @* begin
  heart_pixel = 0;  // Default: no heart pixel
  heart_sprite_x = 0;
  heart_sprite_y = 0;
  trophy_pixel = 0;  // Default: no trophy pixel
  trophy_sprite_x = 0;
  trophy_sprite_y = 0;

  // Heart rendering
  if (current_state == PLAYING || current_state == GAME_OVER) begin
    if (pix_x >= HEART_X && pix_x < HEART_X + 16 && 
        pix_y >= HEART_Y && pix_y < HEART_Y + 16) begin
      // Get the sprite's x and y positions within the 16x16 grid
      heart_sprite_x = pix_x - HEART_X;
      heart_sprite_y = pix_y - HEART_Y;

      // If the sprite bit is set, we have a heart pixel
      if (heart_sprite[heart_sprite_y][heart_sprite_x])
        heart_pixel = 1;
    end
  end

  // Trophy rendering (only in GAME_WON state)
  if (current_state == GAME_WON) begin
    if (pix_x >= TROPHY_X && pix_x < TROPHY_X + TROPHY_WIDTH &&
        pix_y >= TROPHY_Y && pix_y < TROPHY_Y + TROPHY_HEIGHT) begin
      // Calculate the sprite's relative x and y positions
      trophy_sprite_x = pix_x - TROPHY_X;
      trophy_sprite_y = pix_y - TROPHY_Y;
      
      // Check if the current sprite bit is set
      if (trophy_sprite[trophy_sprite_y][trophy_sprite_x])
        trophy_pixel = 1;
    end
  end

  // ----- Barrier Rendering Start -----
  // Initialize barrier_pixel
  barrier_pixel = 0;

  // Barrier 0
  if (barrier_hitpoints[0] > 0 &&
      pix_x >= barrier_x0 && pix_x < barrier_x0 + BARRIER_WIDTH &&
      pix_y >= barrier_y && pix_y < barrier_y + BARRIER_HEIGHT) begin
    barrier_pixel = 1;
  end

  // Barrier 1
  if (barrier_hitpoints[1] > 0 &&
      pix_x >= barrier_x1 && pix_x < barrier_x1 + BARRIER_WIDTH &&
      pix_y >= barrier_y && pix_y < barrier_y + BARRIER_HEIGHT) begin
    barrier_pixel = 1;
  end

  // Barrier 2
  if (barrier_hitpoints[2] > 0 &&
      pix_x >= barrier_x2 && pix_x < barrier_x2 + BARRIER_WIDTH &&
      pix_y >= barrier_y && pix_y < barrier_y + BARRIER_HEIGHT) begin
    barrier_pixel = 1;
  end

  // Barrier 3
  if (barrier_hitpoints[3] > 0 &&
      pix_x >= barrier_x3 && pix_x < barrier_x3 + BARRIER_WIDTH &&
      pix_y >= barrier_y && pix_y < barrier_y + BARRIER_HEIGHT) begin
    barrier_pixel = 1;
  end
  // ----- Barrier Rendering End -----
end

wire health_pixel = (
  pix_x >= HEALTH_DIGIT_X && 
  pix_x < HEALTH_DIGIT_X + DIGIT_WIDTH && 
  pix_y >= HEALTH_DIGIT_Y && 
  pix_y < HEALTH_DIGIT_Y + DIGIT_HEIGHT && 
  digit_segment(digit_segments[digit_health], pix_x, pix_y, HEALTH_DIGIT_X, HEALTH_DIGIT_Y)
);

// Render the score digits on the screen
wire score_pixel = 
    (pix_x >= DIGIT2_X && pix_x < DIGIT2_X + DIGIT_WIDTH && pix_y >= DIGIT_Y && pix_y < DIGIT_Y + DIGIT_HEIGHT && 
     digit_segment(digit_segments[digit2], pix_x, pix_y, DIGIT2_X, DIGIT_Y)) ||
    (pix_x >= DIGIT1_X && pix_x < DIGIT1_X + DIGIT_WIDTH && pix_y >= DIGIT_Y && pix_y < DIGIT_Y + DIGIT_HEIGHT && 
     digit_segment(digit_segments[digit1], pix_x, pix_y, DIGIT1_X, DIGIT_Y)) ||
    (pix_x >= DIGIT0_X && pix_x < DIGIT0_X + DIGIT_WIDTH && pix_y >= DIGIT_Y && pix_y < DIGIT_Y + DIGIT_HEIGHT && 
     digit_segment(digit_segments[digit0], pix_x, pix_y, DIGIT0_X, DIGIT_Y));

// VGA Output Assignments
assign R = video_active ? (
    (alien_pixel ? alien_color[2] : 1'b0) ||
    (bullet_pixel ? 1'b1 : 1'b0) ||
    (score_pixel ? 1'b1 : 1'b0) ||
    (health_pixel ? 1'b1 : 1'b0) ||
    (heart_pixel ? 1'b1 : 1'b0) ||
    (trophy_pixel ? 1'b1 : 1'b0)
) : 1'b0;

assign G = video_active ? (
    (alien_pixel ? alien_color[1] : 1'b0) ||
    (bullet_pixel ? 1'b1 : 1'b0) ||
    (shooter_pixel ? 1'b1 : 1'b0) ||
    (trophy_pixel ? 1'b1 : 1'b0) ||
    (barrier_pixel ? 1'b1 : 1'b0) // Added barrier_pixel
) : 1'b0;

assign B = video_active ? (
    (alien_pixel ? alien_color[0] : 1'b0) ||
    (bullet_pixel ? 1'b1 : 1'b0) ||
    (shooter_pixel ? 1'b1 : 1'b0) ||
    (health_pixel ? 1'b1 : 1'b0)
) : 1'b0;

// State Machine Implementation

// State transition logic
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    current_state <= PLAYING;
  end else begin
    current_state <= next_state;
  end
end

// Next state logic
always @(*) begin
  case (current_state)
    PLAYING: begin
      if (game_won_flag)
        next_state = GAME_WON;
      else if (game_over_flag)
        next_state = GAME_OVER;
      else
        next_state = PLAYING;
    end
    GAME_WON: begin
      // Transition to PLAYING after a delay or user input
      // For simplicity, we'll reset immediately
      next_state = PLAYING;
    end
    GAME_OVER: begin
      // Transition to PLAYING after a delay or user input
      // For simplicity, we'll reset immediately
      next_state = PLAYING;
    end
    default: next_state = PLAYING;
  endcase
end

endmodule
