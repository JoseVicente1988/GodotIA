@tool
extends EditorPlugin

# ============================================================================
# Señales del Plugin Wikiiii
# ============================================================================
signal download_completed(output_dir: String)
signal download_progress(current: int, total: int)
signal download_failed(error: String)

# ============================================================================
# Constantes y Variables
# ============================================================================
const REPO_URL = "https://raw.githubusercontent.com/JoseVicente1988/GodotIA/refs/heads/main/Version.txt?token=GHSAT0AAAAAADCC453N7NUQH3IX77KP64JSZ734SDQ"
const ZIP_URL = "https://github.com/JoseVicente1988/GodotIA/archive/refs/heads/main.zip"

var zip_save_path := "res://Addons/IA/Temp/Addon_IA_update.zip"  # Ruta del ZIP descargado
var extraction_path := "res://Addons/"  # Ruta para extraer los archivos
var new_version: String = ""
var update_dialog_shown := false
var current_request_url := ""

var dock
var progress_window: Window
var progress_bar: ProgressBar
var http_request: HTTPRequest

# Ruta del archivo local que contiene la versión actual
const VERSION_FILE_PATH = "res://Addons/IA/Version.txt"

# ============================================================================
# Inicialización y Limpieza
# ============================================================================
func _enter_tree():
	# Instanciar y registrar el dock del plugin
	dock = preload("res://Addons/IA/IA.tscn").instantiate()
	add_control_to_bottom_panel(dock, "🔆 IA")
	
	# Crear y añadir HTTPRequest
	http_request = HTTPRequest.new()
	add_child(http_request)
	
	# Configurar la ventana de progreso
	progress_window = Window.new()
	progress_window.title = "Descargando actualización..."
	progress_window.size = Vector2(400, 100)
	progress_window.visible = false
	
	progress_bar = ProgressBar.new()
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.custom_minimum_size = Vector2(360, 24)
	progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	progress_bar.position = Vector2(progress_window.size.x / 20, progress_window.size.y / 3)
	progress_bar.value = 0
	
	progress_window.add_child(progress_bar)
	add_child(progress_window)
	
	http_request.request_completed.connect(_on_http_request_completed)

func _ready():
	call_deferred("check_for_updates")

func _exit_tree():
	# Asegurarse de cerrar cualquier diálogo modal creado por el plugin
	for child in get_children():
		if child is ConfirmationDialog:
			child.queue_free()
			
	remove_control_from_bottom_panel(dock)
	dock.queue_free()

# ============================================================================
# Comprobación de Actualización
# ============================================================================
func check_for_updates():
	if update_dialog_shown:
		return
	current_request_url = REPO_URL
	var error = http_request.request(REPO_URL)
	if error != OK:
		push_error("Error al conectar con GitHub: " + str(error))

func _on_http_request_completed(result: int, response_code: int, headers: Array, body: PackedByteArray):
	if current_request_url == REPO_URL:
		_on_version_check_completed(result, response_code, headers, body)
	elif current_request_url == ZIP_URL:
		_on_zip_download_completed(result, response_code, headers, body)

func _on_version_check_completed(result: int, response_code: int, headers: Array, body: PackedByteArray):
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("Error al verificar versión: %s / Código: %s" % [result, response_code])
		return
	
	# Leer la versión desde el archivo local
	var local_version = _read_local_version()

	var remote_version = body.get_string_from_utf8().strip_edges()
	
	if remote_version != local_version and not update_dialog_shown:
		update_dialog_shown = true
		new_version = remote_version
		show_update_dialog()

# Leer la versión desde el archivo local
func _read_local_version() -> String:
	var file = FileAccess.open(VERSION_FILE_PATH, FileAccess.READ)
	if file:
		var version = file.get_line().strip_edges()  # Leer y limpiar la primera línea
		file.close()
		return version
	else:
		push_error("No se pudo abrir el archivo de versión local en: %s" % VERSION_FILE_PATH)
		return ""

# ============================================================================
# Manejo del Diálogo y Actualización
# ============================================================================
func show_update_dialog():
	# Crear y configurar el diálogo de confirmación
	var dialog = ConfirmationDialog.new()
	# Desactivar exclusividad para que no intente ser la única ventana modal
	dialog.exclusive = false
	dialog.title = "Actualización disponible"
	dialog.dialog_text = "Versión %s disponible (tienes %s)\n¿Actualizar ahora?" % [new_version, _read_local_version()]
	dialog.confirmed.connect(_on_update_confirmed)
	
	# Reparentamos el diálogo dentro del dock para ayudar a evitar conflictos
	dock.add_child(dialog)
	
	# Diferir el popup para dar tiempo a que se resuelvan conflictos
	call_deferred("_popup_dialog", dialog)

func _popup_dialog(dialog: ConfirmationDialog) -> void:
	dialog.popup_centered()

func _on_update_confirmed():
	download_update()

# ============================================================================
# Descarga del ZIP y Progreso
# ============================================================================
func download_update():
	progress_bar.value = 0
	progress_window.popup_centered()
	
	current_request_url = ZIP_URL
	var err = http_request.request(ZIP_URL)
	if err != OK:
		push_error("Error iniciando descarga: %s" % err)

func _process(_delta: float):
	if http_request.get_http_client_status() == HTTPClient.STATUS_BODY:
		var total = http_request.get_body_size()
		if total > 0:
			var downloaded = http_request.get_downloaded_bytes()
			progress_bar.value = float(downloaded) / total * 100.0

func _on_zip_download_completed(result: int, response_code: int, headers: Array, body: PackedByteArray):
	progress_window.hide()
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("Error al descargar el ZIP: %s / Código: %s" % [result, response_code])
		return
	
	var file = FileAccess.open(zip_save_path, FileAccess.WRITE)
	if file:
		file.store_buffer(body)
		file.close()
	else:
		push_error("No se pudo guardar el ZIP en: %s" % zip_save_path)
		return
	
	descomprimir_zip(zip_save_path)

	# Eliminar el archivo ZIP después de la descompresión
	eliminar_zip(zip_save_path)




# ============================================================================
# Función para eliminar el archivo ZIP
# ============================================================================
func eliminar_zip(file_path: String):
	if FileAccess.file_exists(file_path):  # Comprobar si el archivo existe
		var dir_access = DirAccess.open(file_path.get_base_dir())  # Obtener acceso al directorio del archivo
		if dir_access:
			var error = dir_access.remove(file_path)  # Eliminar el archivo
			if error == OK:
				print("Archivo ZIP eliminado correctamente: %s" % file_path)
			else:
				push_error("Error al intentar eliminar el archivo ZIP: %s (Código de error: %s)" % [file_path, error])
		else:
			push_error("No se pudo obtener acceso al directorio de: %s" % file_path)
	else:
		print("El archivo ZIP no se encontró: %s" % file_path)

# ============================================================================
# Extracción del ZIP
# ============================================================================
func descomprimir_zip(path: String):
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("No se pudo abrir el archivo ZIP: " + path)
		return
	var zip_buffer: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	
	var zip = ZIPReader.new()
	# Usar el buffer leído para abrir el ZIP
	var err = zip.open(zip_save_path)
	if err != OK:
		push_error("No se pudo abrir el ZIP: %s" % str(err))
		return
	
	# Ajustar la ruta de extracción al directorio "res://Addons/"
	DirAccess.make_dir_recursive_absolute(extraction_path)
	
	# Obtener la lista de archivos del ZIP y extraerlos
	var files_list: PackedStringArray = zip.get_files()
	for file_path in files_list:
		if file_path.ends_with("/"):
			continue  # Saltar directorios

		var file_data: PackedByteArray = zip.read_file(file_path)
		var full_path = extraction_path + file_path
		var dir_path = full_path.get_base_dir()
		DirAccess.make_dir_recursive_absolute(dir_path)
		
		var out_file = FileAccess.open(full_path, FileAccess.WRITE)
		if out_file:
			out_file.store_buffer(file_data)
			out_file.close()
		else:
			push_error("Error al escribir archivo: %s" % full_path)
	
	print("Descompresión completa en: ", extraction_path)
	emit_signal("download_completed", extraction_path)
