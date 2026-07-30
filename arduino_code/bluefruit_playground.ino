/*********************************************************************
 This is an example for our nRF52 based Bluefruit LE modules

 Pick one up today in the adafruit shop!

 Adafruit invests time and resources providing this open source code,
 please support Adafruit and open-source hardware by purchasing
 products from Adafruit!

 MIT license, check LICENSE for more information
 All text above, and the splash screen below must be included in
 any redistribution
*********************************************************************/

/* This sketch demonstrate the BLE Adafruit Service that is used with
 * "Adafruit Bluefruit Playground" app. Supported boards are
 *  - Circuit Playground Bluefruit : https://www.adafruit.com/product/4333
 *  - CLUE nRF52840 : https://www.adafruit.com/product/4500
 *  - Feather Sense : https://www.adafruit.com/product/4516
 */

#include <SPI.h>
#include <SdFat.h>
#include <PDM.h>
#include <Adafruit_LittleFS.h>
#include <InternalFileSystem.h>
#include <bluefruit.h>
#include <BLEAdafruitService.h>

//------------- Circuit Playground Bluefruit -------------//
#if defined(ARDUINO_NRF52840_CIRCUITPLAY)

#include <Adafruit_CircuitPlayground.h>

#define DEVICE_NAME       "CPlay"
#define NEOPIXEL_COUNT    10

uint16_t measure_temperature(uint8_t* buf, uint16_t bufsize)
{
  float temp = CircuitPlayground.temperature();
  memcpy(buf, &temp, 4);
  return 4;
}

uint16_t measure_light(uint8_t* buf, uint16_t bufsize)
{
  float lux;
  lux = CircuitPlayground.lightSensor();
  memcpy(buf, &lux, 4);
  return 4;
}

uint16_t measure_button(uint8_t* buf, uint16_t bufsize)
{
  uint32_t button = 0;

  button |= ( CircuitPlayground.slideSwitch() ? 0x01 : 0x00 );
  button |= ( CircuitPlayground.leftButton()  ? 0x02 : 0x00 );
  button |= ( CircuitPlayground.rightButton() ? 0x04 : 0x00 );

  memcpy(buf, &button, 4);
  return 4;
}

//------------- CLUE & Feather Sense -------------//
#elif defined(ARDUINO_NRF52840_CLUE) || defined(ARDUINO_NRF52840_FEATHER_SENSE)

#include <Adafruit_APDS9960.h>
#include <Adafruit_BMP280.h>
#include <Adafruit_LIS3MDL.h>
#include <Adafruit_LSM6DS33.h>
#include <Adafruit_SHT31.h>

#include <Adafruit_SPIFlash.h>
#include <Adafruit_AHRS.h>
#include <Adafruit_Sensor_Calibration.h>

#if defined(ARDUINO_NRF52840_CLUE)
  #define DEVICE_NAME     "CLUE"
#else
  #define DEVICE_NAME     "Sense"
#endif

#define NEOPIXEL_COUNT    1

BLEAdafruitBaro       bleBaro;
BLEAdafruitColor      bleColor;
BLEAdafruitGesture    bleGesture;
BLEAdafruitHumid      bleHumid;
BLEAdafruitProximity  bleProximity;
BLEAdafruitQuaternion bleQuater;
BLEAdafruitGyro       bleGyro;

Adafruit_LSM6DS33 lsm6ds33; // Gyro and Accel
Adafruit_LIS3MDL  lis3mdl;  // Magnetometer
Adafruit_APDS9960 apds9960; // Proximity, Light, Gesture, Color
Adafruit_BMP280   bmp280;   // Temperature, Barometric
Adafruit_SHT31    sht30;    // Humid

// pick your filter! slower == better quality output
//Adafruit_NXPSensorFusion filter; // slowest
//Adafruit_Madgwick filter;  // faster than NXP
Adafruit_Mahony filter;  // fastest/smalleset

// Sensor calibration
#define FILE_SENSOR_CALIB       "sensor_calib.json"
Adafruit_Sensor_Calibration_SDFat cal;

Adafruit_FlashTransport_QSPI flashTransport;
Adafruit_SPIFlash flash(&flashTransport);
FatFileSystem fatfs;

void light_enable_callback(uint16_t conn_hdl, bool enabled)
{
  (void) conn_hdl;
  apds9960.enableColor(enabled);
}

uint16_t measure_light(uint8_t* buf, uint16_t bufsize)
{
  float lux;
  uint16_t r, g, b, c;

  apds9960.getColorData(&r, &g, &b, &c);

  lux = c;
  memcpy(buf, &lux, 4);
  return 4;
}

void color_enable_callback(uint16_t conn_hdl, bool enabled)
{
  (void) conn_hdl;

  apds9960.enableColor(enabled);

#ifdef ARDUINO_NRF52840_CLUE
  digitalWrite(PIN_LED2, enabled);
#endif
}

uint16_t measure_color(uint8_t* buf, uint16_t bufsize)
{
  uint16_t rgb[3];
  uint16_t c;
  (void) c;

  apds9960.getColorData(rgb+0, rgb+1, rgb+2, &c);

  memcpy(buf, rgb, sizeof(rgb));
  return sizeof(rgb);
}

void gesture_enable_callback(uint16_t conn_hdl, bool enabled)
{
  (void) conn_hdl;
  apds9960.enableProximity(enabled);
  apds9960.enableGesture(enabled);
}

uint16_t measure_gesture(uint8_t* buf, uint16_t bufsize)
{
  uint8_t gesture = apds9960.readGesture();
  if (gesture == 0) return 0; // skip no gesture value

  // APDS9960 sensor position is rotated 90 degree left on CLUE
  // We will need to correct that by rotating right for user convenience
  uint8_t const clue_rotation[] = { 0, APDS9960_LEFT, APDS9960_RIGHT, APDS9960_DOWN, APDS9960_UP };
  buf[0] = clue_rotation[gesture];

  return 1;
}

void proximity_enable_callback(uint16_t conn_hdl, bool enabled)
{
  (void) conn_hdl;
  apds9960.enableProximity(enabled);
}

uint16_t measure_proximity(uint8_t* buf, uint16_t bufsize)
{
  // APDS is only 8-bit, we better to map it to 16-bit value
  uint8_t data8 = apds9960.readProximity();
  uint16_t data16 = (uint16_t) map(data8, 0, UINT8_MAX, 0, UINT16_MAX);

  memcpy(buf, &data16, 2);
  return 2;
}

uint16_t measure_button(uint8_t* buf, uint16_t bufsize)
{
  // Button is active LOW on most board except CPlay
  // No slide switch

  uint32_t button = 0;
  button |= ( digitalRead(PIN_BUTTON1) ? 0x00 : 0x02 );
#if defined(PIN_BUTTON2)
  button |= ( digitalRead(PIN_BUTTON2) ? 0x00 : 0x04 );
#endif

  // Check USB connection and charging status
  bool is_usb = (NRF_POWER->USBREGSTATUS & POWER_USBREGSTATUS_VBUSDETECT_Msk);
  if (is_usb) {
    button |= 0x10; // Bit 4: USB Power Connected
    
    // Check if battery is actively bulk charging (< 95%)
    uint8_t batt = read_battery_percentage();
    if (batt < 95) {
      button |= 0x20; // Bit 5: Actively Charging
    }
  }

  memcpy(buf, &button, 4);
  return 4;
}

uint16_t measure_humid(uint8_t* buf, uint16_t bufsize)
{
  float humid = sht30.readHumidity();
  memcpy(buf, &humid, 4);
  return 4;
}

uint16_t measure_gyro(uint8_t* buf, uint16_t bufsize)
{
  sensors_event_t accel;
  sensors_event_t gyro;
  sensors_event_t temp;
  lsm6ds33.getEvent(&accel, &gyro, &temp);

  float data[3] = { gyro.gyro.x, gyro.gyro.y, gyro.gyro.z };
  memcpy(buf, data, min(bufsize, (uint16_t)12));
  return 12;
}

uint16_t measure_temperature(uint8_t* buf, uint16_t bufsize)
{
  float temp = bmp280.readTemperature();
  
  // Check USB connection
  bool is_usb = (NRF_POWER->USBREGSTATUS & POWER_USBREGSTATUS_VBUSDETECT_Msk);
  
  // Apply a dynamic self-heating calibration offset:
  // - On battery power: subtract 2.5 degrees C
  // - On USB power (fully charged / idle): subtract 4.0 degrees C
  // - On USB power (actively charging, batt < 95%): subtract 7.5 degrees C
  if (is_usb) {
    uint8_t batt = read_battery_percentage();
    if (batt < 95) {
      temp = temp - 7.5; // Active charging
    } else {
      temp = temp - 4.0; // USB Connected, but fully charged (idle)
    }
  } else {
    temp = temp - 2.5; // Running on battery
  }
  
  memcpy(buf, &temp, 4);
  return 4;
}

#else
  #error "Board is not supported"

#endif // end of board

//--------------------------------------------------------------------+
// Common for all Boards
//--------------------------------------------------------------------+

// BLE Service
BLEDfu  bledfu;  // OTA DFU service
BLEDis  bledis;  // device information
BLEUart bleuart; // uart over ble
BLEBas  blebas;  // battery

// Adafruit Service: ADAFxx-C332-42A8-93BD-25E905756CB8
BLEAdafruitTemperature        bleTemp;
BLEAdafruitAccel              bleAccel;
BLEAdafruitLightSensor        bleLight;
BLEAdafruitButton             bleButton;
BLEAdafruitTone               bleTone;
BLEAdafruitAddressablePixel   blePixel;
BLEAdafruitSound              bleSound;

Adafruit_NeoPixel strip = Adafruit_NeoPixel(NEOPIXEL_COUNT, PIN_NEOPIXEL, NEO_GRB + NEO_KHZ800);
int16_t pdmSample[256]; // sound samples
uint16_t pdmByteCount = 0;

//void pdm_plotter(uint16_t count)
//{
//  for (int i = 0; i < count/2; i++) Serial.println(pdmSample[i]);
//}

uint16_t measure_sound(uint8_t* buf, uint16_t bufsize)
{
  uint16_t const len = min(bufsize, pdmByteCount);

  if ( len ) memcpy(buf, pdmSample, len);
  pdmByteCount = 0; // clear count

//  if (len) ada_callback(NULL, 0, pdm_plotter, len);

  return len;
}

uint16_t measure_accel(uint8_t* buf, uint16_t bufsize)
{
  float x = 0, y = 0, z = 0;
#if defined(ARDUINO_NRF52840_CIRCUITPLAY)
  x = CircuitPlayground.motionX();
  y = CircuitPlayground.motionY();
  z = CircuitPlayground.motionZ();
#else
  sensors_event_t accel;
  sensors_event_t gyro;
  sensors_event_t temp;
  lsm6ds33.getEvent(&accel, &gyro, &temp);
  x = accel.acceleration.x;
  y = accel.acceleration.y;
  z = accel.acceleration.z;
#endif

  float data[3] = { x, y, z };
  memcpy(buf, data, min(bufsize, (uint16_t)12));
  return 12;
}

uint8_t read_battery_percentage() {
#if defined(ARDUINO_NRF52840_CIRCUITPLAY)
  float voltage = CircuitPlayground.batteryVoltage();
#else
  // For CLUE & Feather Sense
  float raw = analogRead(A6);
  float voltage = (raw * 3.6 / 1024.0) * 2.0;
#endif

  // LiPo battery voltage ranges from ~3.2V (0%) to 4.2V (100%)
  int percentage = (int) ((voltage - 3.2) / (4.2 - 3.2) * 100.0);
  if (percentage > 100) percentage = 100;
  if (percentage < 0) percentage = 0;
  
  return (uint8_t) percentage;
}

unsigned long lastBatteryUpdate = 0;
uint32_t boot_reset_reason = 0;

//--------------------------------------------------------------------+
// Codes
//--------------------------------------------------------------------+
void setup()
{
  boot_reset_reason = NRF_POWER->RESETREAS;
  NRF_POWER->RESETREAS = 0xFFFFFFFF; // Clear reset reasons for next time

  Adafruit_Sensor* accel_sensor;

  Serial.begin(115200);
//  while(!Serial) delay(10); // wait for native USB

#if defined ARDUINO_NRF52840_CIRCUITPLAY
  CircuitPlayground.begin();

  accel_sensor = &CircuitPlayground.lis;
#else

  // Button
  pinMode(PIN_BUTTON1, INPUT_PULLUP);
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, HIGH); // Turn on Red LED to show device is ON
#if defined(PIN_BUTTON2)
  pinMode(PIN_BUTTON2, INPUT_PULLUP);
#endif

#ifdef ARDUINO_NRF52840_CLUE
  // White LEDs for color sensing
  pinMode(PIN_LED2, OUTPUT);
  digitalWrite(PIN_LED2, LOW);
#endif

  apds9960.begin();
  bmp280.begin();
  sht30.begin(0x44);
  lsm6ds33.begin_I2C();
  lis3mdl.begin_I2C();

  // set lowest range
  lsm6ds33.setAccelRange(LSM6DS_ACCEL_RANGE_2_G);
  lsm6ds33.setGyroRange(LSM6DS_GYRO_RANGE_250_DPS);
  lis3mdl.setRange(LIS3MDL_RANGE_4_GAUSS);

  // set slightly above refresh rate
  lsm6ds33.setAccelDataRate(LSM6DS_RATE_104_HZ);
  lsm6ds33.setGyroDataRate(LSM6DS_RATE_104_HZ);
  lis3mdl.setDataRate(LIS3MDL_DATARATE_1000_HZ);
  lis3mdl.setPerformanceMode(LIS3MDL_MEDIUMMODE);
  lis3mdl.setOperationMode(LIS3MDL_CONTINUOUSMODE);

  // Increase I2C speed to 400 Khz
  Wire.setClock(400000);

  accel_sensor = lsm6ds33.getAccelerometerSensor();

  // Init flash, filesystem and calibration & load calib json
  flash.begin();
  fatfs.begin(&flash);
  cal.begin(FILE_SENSOR_CALIB, &fatfs);
  cal.loadCalibration();
#endif

  // 1 channel (mono mode) with 16 kHz sample rate
  PDM.onReceive(onPDMdata);
  PDM.begin(1, 16000);

  Serial.println("Bluefruit Playground Example");
  Serial.println("---------------------------\n");

  // Setup the BLE LED to be enabled on CONNECT
  // Note: This is actually the default behaviour, but provided
  // here in case you want to control this LED manually via PIN 19
  Bluefruit.autoConnLed(false);

  // Config the peripheral connection with maximum bandwidth 
  // more SRAM required by SoftDevice
  // Note: All config***() function must be called before begin()
  Bluefruit.configPrphBandwidth(BANDWIDTH_MAX);

  Bluefruit.begin();
  Bluefruit.setTxPower(8);    // Check bluefruit.h for supported values
  Bluefruit.setName(DEVICE_NAME);
  Bluefruit.Periph.setConnectCallback(connect_callback);
  Bluefruit.Periph.setDisconnectCallback(disconnect_callback);

  // To be consistent OTA DFU should be added first if it exists
  bledfu.begin();

  // Configure and Start Device Information Service
  bledis.setManufacturer("Adafruit Industries");
  bledis.begin();

  // Configure and Start BLE Uart Service
  bleuart.begin();

  // Start BLE Battery Service
  blebas.begin();
  blebas.write(100);

  //------------- Adafruit Service -------------//
  bleAccel.begin(measure_accel, 100); // Uses callback instead of raw sensor to avoid LSM6DS33 timer conflict

  bleButton.begin(measure_button, 100);
  bleButton.setPeriod(0); // only notify if there is changes with buttons

  strip.begin();
  blePixel.begin(&strip);

  bleSound.begin(1, measure_sound, 100);

  // CPB doesn't support these on-board sensor
#ifdef ARDUINO_NRF52840_CIRCUITPLAY
  bleLight.begin(measure_light, 100);
  bleTemp.begin(measure_temperature, 100);

#else
  bleBaro.begin(bmp280.getPressureSensor(), 100);

  bleColor.begin(measure_color, 100);
  bleColor.setNotifyCallback(color_enable_callback);

  bleGesture.begin(measure_gesture, 10); // sampling is 10 ms
  bleGesture.setPeriod(0); // notify on changes only
  bleGesture.setNotifyCallback(gesture_enable_callback);

  bleHumid.begin(measure_humid, 100);
  bleGyro.begin(measure_gyro, 100);

  bleLight.begin(measure_light, 100);;
  bleLight.setNotifyCallback(light_enable_callback);

  bleProximity.begin(measure_proximity, 100);
  bleProximity.setNotifyCallback(proximity_enable_callback);

  // Quaternion with sensor calibration
  bleQuater.begin(&filter, accel_sensor, lsm6ds33.getGyroSensor(), &lis3mdl);
  bleQuater.setCalibration(&cal);

  bleTemp.begin(measure_temperature, 100);
#endif

#if defined(PIN_BUZZER)
  bleTone.begin(PIN_BUZZER);
#endif

  // Set up and start advertising
  startAdv();

  Serial.println("Please use Adafruit's Bluefruit LE app to connect in UART mode");
  Serial.println("Once connected, enter character(s) that you wish to send");
}

void startAdv(void)
{
  // Advertising packet
  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);

  // Advertising with only board ID
  struct ATTR_PACKED {
    uint16_t mfr_id;
    
    uint8_t  field_len;
    uint16_t field_key;
    uint16_t field_value;
  } mfr_adv;

  mfr_adv.mfr_id = UUID16_COMPANY_ID_ADAFRUIT;
  mfr_adv.field_len = 4;
  mfr_adv.field_key = 1; // board id
  mfr_adv.field_value = USB_PID;

  Bluefruit.Advertising.addManufacturerData(&mfr_adv, sizeof(mfr_adv));

  // Add name to advertising, since there is enough room
  Bluefruit.Advertising.addName();
  
  /* Start Advertising
   * - Enable auto advertising if disconnected
   * - Interval:  fast mode = 20 ms, slow mode = 152.5 ms
   * - Timeout for fast mode is 30 seconds
   * - Start(timeout) with timeout = 0 will advertise forever (until connected)
   * 
   * For recommended advertising interval
   * https://developer.apple.com/library/content/qa/qa1931/_index.html   
   */
  Bluefruit.Advertising.restartOnDisconnect(true);
  Bluefruit.Advertising.setInterval(32, 244);    // in unit of 0.625 ms
  Bluefruit.Advertising.setFastTimeout(30);      // number of seconds in fast mode
  Bluefruit.Advertising.start(0);                // 0 = Don't stop advertising after n seconds  
}

void loop()
{
  // Check if the board button is held for 2 seconds to enter deep sleep
  if (digitalRead(PIN_BUTTON1) == LOW) {
    unsigned long pressStart = millis();
    while (digitalRead(PIN_BUTTON1) == LOW) {
      if (millis() - pressStart > 2000) {
        // Turn off Neopixels and Red LED before sleeping
        strip.clear();
        strip.show();
        digitalWrite(LED_BUILTIN, LOW); // Turn off Red LED to show device is in sleep
        
        // Wait for user to release the button
        while (digitalRead(PIN_BUTTON1) == LOW) {
          delay(10);
        }
        delay(100); // Debounce
        
        Serial.println("Entering System OFF...");
        Serial.flush();

        // 1. Power down sensors
#if defined(ARDUINO_NRF52840_CLUE) || defined(ARDUINO_NRF52840_FEATHER_SENSE)
        lsm6ds33.setAccelDataRate(LSM6DS_RATE_SHUTDOWN);
        lsm6ds33.setGyroDataRate(LSM6DS_RATE_SHUTDOWN);
        lis3mdl.setOperationMode(LIS3MDL_POWERDOWNMODE);
        apds9960.enable(false);
        bmp280.setSampling(Adafruit_BMP280::MODE_SLEEP);
#endif

        // 2. Power down external SPI Flash
        flashTransport.runCommand(0xB9); // Send Deep Power-Down command (0xB9) to SPI flash chip
        flash.end();                     // Uninitialize flash driver and uninit QSPI peripheral

#if defined(PIN_QSPI_CS)
        pinMode(PIN_QSPI_CS, OUTPUT);
        digitalWrite(PIN_QSPI_CS, HIGH); // Explicitly drive QSPI CS high to prevent floating/leakage
#endif

        // Enter Nordic System OFF mode (deep sleep).
        // Waking up is done by pressing the Reset button (nearest to USB).
        sd_power_system_off();
        
        // Fallback: If sd_power_system_off() returns/fails (e.g. if SoftDevice is busy),
        // force System OFF directly via the hardware register.
        NRF_POWER->SYSTEMOFF = 1;
        
        // If it still hasn't shut down, halt execution to prevent battery drain
        while (1) {
          __WFI(); // Wait for Interrupt (enters sleep mode of the CPU core)
        }
      }
      delay(10);
    }
  }

  // Update the battery level and print sensor data every 10 seconds
  if (millis() - lastBatteryUpdate > 10000) {
    lastBatteryUpdate = millis();
    uint8_t batt = read_battery_percentage();
    blebas.write(batt);
    blebas.notify(batt);
    
    // Print battery info to Serial Monitor
    Serial.print("Boot Reset Reason: 0x");
    Serial.println(boot_reset_reason, HEX);

    Serial.print("Battery Raw ADC: ");
    Serial.print(analogRead(A6));
    Serial.print(" | Percentage: ");
    Serial.print(batt);
    Serial.println("%");

    // Read and print Accelerometer data
    sensors_event_t accel;
    sensors_event_t gyro;
    sensors_event_t temp;
    lsm6ds33.getEvent(&accel, &gyro, &temp);
    Serial.print("Accel X: ");
    Serial.print(accel.acceleration.x);
    Serial.print(" | Y: ");
    Serial.print(accel.acceleration.y);
    Serial.print(" | Z: ");
    Serial.println(accel.acceleration.z);
  }
}

// callback invoked when central connects
void connect_callback(uint16_t conn_handle)
{
  // Get the reference to current connection
  BLEConnection* connection = Bluefruit.Connection(conn_handle);

  char central_name[32] = { 0 };
  connection->getPeerName(central_name, sizeof(central_name));

  Serial.print("Connected to ");
  Serial.println(central_name);
}

/**
 * Callback invoked when a connection is dropped
 * @param conn_handle connection where this event happens
 * @param reason is a BLE_HCI_STATUS_CODE which can be found in ble_hci.h
 */
void disconnect_callback(uint16_t conn_handle, uint8_t reason)
{
  (void) conn_handle;
  (void) reason;

#if defined(ARDUINO_NRF52840_CLUE) || defined(ARDUINO_NRF52840_FEATHER_SENSE)
  apds9960.enableGesture(false);
  apds9960.enableProximity(false);
  apds9960.enableColor(false);
#endif

#ifdef ARDUINO_NRF52840_CLUE
  digitalWrite(PIN_LED2, LOW);
#endif

  Serial.println();
  Serial.print("Disconnected, reason = 0x"); Serial.println(reason, HEX);
}


void onPDMdata()
{
  // query the number of bytes available
  pdmByteCount = PDM.available();

  // read into the sample buffer
  PDM.read(pdmSample, pdmByteCount);
}
