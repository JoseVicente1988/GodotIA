@tool
extends Control

# ============================================================================
# Configuración de la API
# ============================================================================
const API_URL = "https://api.together.xyz/v1/completions"  # URL de la API para enviar consultas
var api_key = "b5f1ee11e609525f205c18dfaa1e33e36ad9f714e0ac1a03b56cb8d79289c1f1"  # Clave API (reemplaza con una válida)

# ============================================================================
# Variables
# ============================================================================
var Audio : bool = false  # Determina si la respuesta se leerá en voz alta
var http_request = HTTPRequest.new()  # Nodo para enviar solicitudes HTTP

# ============================================================================
# Inicialización
# ============================================================================
func _ready():
	# Añadir HTTPRequest al árbol de nodos y conectar su señal para manejar respuestas
	add_child(http_request)
	http_request.request_completed.connect(_on_http_request_completed)

# ============================================================================
# Funciones
# ============================================================================

# Enviar solicitud a la API con el prompt especificado
func hacer_consulta(prompt: String):
	# Configurar encabezados para la solicitud
	var headers = [
		"Authorization: Bearer %s" % api_key,  # Autorización con clave API
		"Content-Type: application/json"       # Indica que el cuerpo de la solicitud está en formato JSON
	]

	# Configurar cuerpo de la solicitud
	var cuerpo_peticion = {
		"role": "user",  # Rol del usuario para la API
		"model": "meta-llama/Llama-4-Maverick-17B-128E-Instruct-FP8",  # Especificación del modelo utilizado
		"prompt": "Trabajas exclusivamente con godot, debes responder unicamente la peticion, sin " +
				  "documentarlo, solo el codigo, no quiero simbolos raros como (''') " + prompt,
		"max_tokens": 512,  # Número máximo de tokens en la respuesta
		"temperature": 1,   # Controla la creatividad del modelo en la respuesta
	}

	# Enviar la solicitud mediante HTTPRequest
	var error = http_request.request(API_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(cuerpo_peticion))
	if error != OK:
		print("Error al enviar la solicitud:", error)
		# Actualizar el Label en la interfaz para indicar que la solicitud fue enviada
		$VBoxContainer/Label.text = "[center]Solicitud enviada. A la espera de la respuesta...[/center]"

# Procesar la respuesta recibida de la API
func _on_http_request_completed(resultado: int, codigo_respuesta: int, cabeceras: PackedStringArray, cuerpo: PackedByteArray):
	# Validar éxito de la conexión
	if resultado != HTTPRequest.RESULT_SUCCESS:
		print("Error en la conexión:", resultado)
		return
	
	# Validar código de respuesta HTTP
	if codigo_respuesta != 200:
		print("Error HTTP:", codigo_respuesta)
		return

	# Parsear la respuesta JSON desde el cuerpo recibido
	var json = JSON.new()
	var error_parseo = json.parse(cuerpo.get_string_from_utf8())
	if error_parseo != OK:
		print("Error al parsear JSON:", json.get_error_message())
		return

	# Extraer datos de la respuesta
	var respuesta = json.get_data()
	if respuesta and respuesta.has("choices") and respuesta["choices"].size() > 0:
		var texto_respuesta = respuesta["choices"][0]["text"]
		# Actualizar el Label en la interfaz con la respuesta de la API
		$VBoxContainer/Label.call_deferred("set_text", "[center]" + texto_respuesta.strip_edges() + "[/center]")

		# Detener cualquier voz activa en caso de que se reproduzca audio
		DisplayServer.tts_stop()
		if Audio:
			# Configurar y reproducir la respuesta como audio
			var voice = DisplayServer.tts_get_voices_for_language("es")  # Buscar voces disponibles en español
			var voice_id = voice[0]  # Seleccionar la primera voz encontrada
			DisplayServer.tts_speak(texto_respuesta, voice_id, 100)  # Leer el texto con velocidad de 100

	else:
		# Indicar que la respuesta no contiene datos válidos
		$VBoxContainer/Label.text = str("La respuesta no contiene datos válidos")

# Función llamada al presionar el botón (envía la consulta)
func _on_button_pressed() -> void:
	print(str($VBoxContainer/HBoxContainer/LineEdit.text))
	hacer_consulta($VBoxContainer/HBoxContainer/LineEdit.text)
	# Limpiar el campo de texto después de enviar la consulta
	$VBoxContainer/HBoxContainer/LineEdit.text = ""

# Función llamada al enviar texto desde el LineEdit (envía la consulta)
func _on_line_edit_text_submitted(new_text: String) -> void:
	hacer_consulta(new_text)
	# Limpiar el campo de texto después de enviar la consulta
	$VBoxContainer/HBoxContainer/LineEdit.text = ""

# Función llamada al activar/desactivar el CheckBox (controla si se usa audio)
func _on_check_box_toggled(toggled_on: bool) -> void:
	Audio = toggled_on
