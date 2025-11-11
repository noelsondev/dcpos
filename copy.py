import os

# Carpeta base
LIB_DIR = "lib"
# Archivo de salida
OUTPUT_FILE = "all_in_one.dart"

def merge_dart_files():
    with open(OUTPUT_FILE, "w", encoding="utf-8") as outfile:
        for root, _, files in os.walk(LIB_DIR):
            for file in files:
                # Solo procesar archivos .dart que NO terminen en .g.dart
                if file.endswith(".dart") and not file.endswith(".g.dart"):
                    file_path = os.path.join(root, file)
                    relative_path = os.path.relpath(file_path, LIB_DIR)

                    # Agregar comentario con el nombre del archivo original
                    outfile.write(f"\n\n// ===== Archivo: {relative_path} =====\n")
                    with open(file_path, "r", encoding="utf-8") as infile:
                        outfile.write(infile.read())
                    outfile.write("\n")
    print(f"✅ Archivos .dart (excepto *.g.dart) combinados en '{OUTPUT_FILE}'.")

if __name__ == "__main__":
    merge_dart_files()
