// Smart Vending Machine - ESP32 Serial Relay + Keypad Event Simulator
// Drop produk: DROP_SLOT_11 -> SUCCESS_11
// Tes input: DETECT, 0..9, ACCEPT, CANCEL, atau DECLINED

const uint32_t SERIAL_BAUD_RATE = 115200;
const uint8_t MOTOR_RELAY_PIN = 23;
const bool RELAY_ACTIVE_LEVEL = HIGH;
const unsigned long MOTOR_RUN_TIME_MS = 1500;
const size_t MAX_COMMAND_LENGTH = 40;

String commandBuffer;

bool isValidSlotCode(const String &slotCode) {
  if (slotCode.length() != 2) {
    return false;
  }

  for (size_t index = 0; index < slotCode.length(); index++) {
    const char character = slotCode.charAt(index);
    if (character < '0' || character > '9') {
      return false;
    }
  }

  const int slotNumber = slotCode.toInt();
  return (slotNumber >= 1 && slotNumber <= 45) ||
         (slotNumber >= 51 && slotNumber <= 55);
}

void setRelay(bool active) {
  digitalWrite(
    MOTOR_RELAY_PIN,
    active ? RELAY_ACTIVE_LEVEL : !RELAY_ACTIVE_LEVEL
  );
}

void runMotorForSlot(const String &slotCode) {
  Serial.print(F("BUSY_"));
  Serial.println(slotCode);

  // Satu relay digunakan sebagai simulasi. Untuk mesin nyata, ganti fungsi
  // ini dengan pemilihan channel relay/multiplexer berdasarkan slotCode.
  setRelay(true);
  delay(MOTOR_RUN_TIME_MS);
  setRelay(false);

  Serial.print(F("SUCCESS_"));
  Serial.println(slotCode);
}

// Fungsi-fungsi ini juga dapat dipanggil nanti dari pembacaan keypad/sensor.
void emitUserDetected() {
  Serial.println(F("EVENT_USER_DETECTED"));
}

void emitKeypadDigit(const char digit) {
  Serial.print(F("EVENT_KEY_"));
  Serial.println(digit);
}

void emitKeypadAccept() {
  Serial.println(F("EVENT_ACCEPT"));
}

void emitKeypadCancel() {
  Serial.println(F("EVENT_CANCEL"));
}

bool processTestInput(const String &command) {
  if (command == "DETECT" || command == "TEST_DETECT") {
    emitUserDetected();
    return true;
  }

  if (command == "ACCEPT" || command == "TEST_ACCEPT") {
    emitKeypadAccept();
    return true;
  }

  if (command == "CANCEL" || command == "DECLINED" ||
      command == "TEST_CANCEL" || command == "TEST_DECLINED") {
    emitKeypadCancel();
    return true;
  }

  if (command.length() == 1 && isDigit(command.charAt(0))) {
    emitKeypadDigit(command.charAt(0));
    return true;
  }

  const String keyPrefix = "KEY_";
  const String testKeyPrefix = "TEST_KEY_";
  if (command.startsWith(keyPrefix) && command.length() == 5 &&
      isDigit(command.charAt(4))) {
    emitKeypadDigit(command.charAt(4));
    return true;
  }
  if (command.startsWith(testKeyPrefix) && command.length() == 10 &&
      isDigit(command.charAt(9))) {
    emitKeypadDigit(command.charAt(9));
    return true;
  }

  return false;
}

void processCommand(String command) {
  command.trim();
  command.toUpperCase();
  if (command.isEmpty()) {
    return;
  }

  if (processTestInput(command)) {
    return;
  }

  const String commandPrefix = "DROP_SLOT_";
  if (!command.startsWith(commandPrefix)) {
    Serial.println(F("ERROR_UNKNOWN_COMMAND"));
    return;
  }

  const String slotCode = command.substring(commandPrefix.length());
  if (!isValidSlotCode(slotCode)) {
    Serial.print(F("ERROR_INVALID_SLOT_"));
    Serial.println(slotCode);
    return;
  }

  runMotorForSlot(slotCode);
}

void setup() {
  pinMode(MOTOR_RELAY_PIN, OUTPUT);
  setRelay(false);

  Serial.begin(SERIAL_BAUD_RATE);
  commandBuffer.reserve(MAX_COMMAND_LENGTH);
  Serial.println(F("READY"));
  Serial.println(F("TEST_COMMANDS: DETECT, 0-9, ACCEPT, CANCEL, DECLINED"));
}

void loop() {
  while (Serial.available() > 0) {
    const char incoming = static_cast<char>(Serial.read());

    if (incoming == '\r') {
      continue;
    }

    if (incoming == '\n') {
      processCommand(commandBuffer);
      commandBuffer = "";
      continue;
    }

    if (commandBuffer.length() >= MAX_COMMAND_LENGTH) {
      commandBuffer = "";
      Serial.println(F("ERROR_COMMAND_TOO_LONG"));
      continue;
    }

    commandBuffer += incoming;
  }
}
