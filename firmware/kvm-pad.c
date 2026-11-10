// Caps tap (LT(7, F13)) starts the host's cursor pad; light the letter block while it runs.
// The end conditions mirror snap's: Space, Enter, Esc, Shift+letter, or any non-letter key.
#include QMK_KEYBOARD_H

static bool pad_active = false;

static bool is_letter_block(uint16_t kc) {
    return (kc >= KC_A && kc <= KC_Z) || kc == KC_QUOT || kc == KC_COMM || kc == KC_DOT || kc == KC_SCLN;
}

// Letter-block LED last pressed during the pad, and when; it flashes bright briefly.
static uint8_t  flash_led = 0xFF;
static uint16_t flash_time;
static bool     flash_held = false;

static uint8_t led_of(keyrecord_t *record) {
    uint8_t row = record->event.key.row, col = record->event.key.col;
    return row < MATRIX_ROWS && col < MATRIX_COLS ? g_led_config.matrix_co[row][col] : NO_LED;
}

bool process_record_user(uint16_t keycode, keyrecord_t *record) {
    if (keycode == LT(7, KC_F13)) {
        if (record->tap.count && record->event.pressed) { pad_active = !pad_active; flash_led = 0xFF; }
        return true;
    }
    if (!record->event.pressed) { if (led_of(record) == flash_led) flash_held = false; return true; }
    if (!pad_active) return true;
    if (IS_MODIFIER_KEYCODE(keycode)) return true;
    if (!is_letter_block(keycode) || (get_mods() & MOD_MASK_SHIFT)) { pad_active = false; return true; }
    flash_led = led_of(record);
    flash_time = timer_read();
    flash_held = true;
    return true;
}

// LED index of each letter-block key, top to bottom, left to right (keyboard.json order).
static const uint8_t pad_leds[3][10] = {
    {15, 16, 17, 18, 19, 20, 21, 22, 23, 24},
    {29, 30, 31, 32, 33, 34, 35, 36, 37, 38},
    {42, 43, 44, 45, 46, 47, 48, 49, 50, 51},
};

bool rgb_matrix_indicators_user(void) {
    if (!pad_active) return true;
    for (uint8_t i = 0; i < 64; i++) rgb_matrix_set_color(i, 0, 0, 0);
    for (uint8_t r = 0; r < 3; r++)
        for (uint8_t c = 0; c < 10; c++) rgb_matrix_set_color(pad_leds[r][c], 36, 36, 36);
    // Held keys repeat in the host, so keep the pressed key lit while it is down.
    if (flash_led != 0xFF && (flash_held || timer_elapsed(flash_time) < 180)) rgb_matrix_set_color(flash_led, 255, 255, 255);
    return true;
}
