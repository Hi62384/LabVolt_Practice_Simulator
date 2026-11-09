// LabVolt native backend verification fixture. Compile for Arduino Uno R3.
// Uses real Arduino core pinMode/digitalWrite/delay, not a source translator.
void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
}
void loop() {
  digitalWrite(LED_BUILTIN, HIGH);
  delay(10);
  digitalWrite(LED_BUILTIN, LOW);
  delay(10);
}
