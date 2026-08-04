# Bluefruit Playground

Circuit Playground Bluefruit is the most fun you can have with a circuit board – and Bluefruit Playground makes it even better.

Connect Bluefruit Playground to a Circuit Playground Bluefruit board and you can:

* Control LED color & animation
* View continuous light sensor readings
* View state of built-in buttons & switch
* Turn CPB into a musical instrument
* View orientation based on accelerometer data
* View temperature readings

...all without soldering or writing a single line of code!

**Important:** Open this project in Xcode by using the .xcworkspace file and not the .xcodeproj file

## Feather nRF52840 Sense: System OFF

The firmware at `arduino_code/bluefruit_playground/bluefruit_playground.ino` supports a low-power System OFF mode when running on an Adafruit Feather nRF52840 Sense.

1. Press and hold the **User** button (the button that is not labelled `RESET`) for at least two seconds.
2. Release the button. The NeoPixel flashes green three times, then all board LEDs turn off.
3. The board disconnects from Bluefruit Playground and stops BLE advertising and sensor notifications. It is now in System OFF.
4. Briefly press the **User** button to wake it. The board resets, restarts BLE advertising, and can be connected again from the app.

The `RESET` button also restarts the board, but it does not enter or wake the normal System OFF flow.
