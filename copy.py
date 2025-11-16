import os
#type: ignore;

# Carpeta donde están los .dart
SOURCE_DIR = "lib"
# Archivo de salida
OUTPUT_FILE = "merged.dart"

def should_include(file_name):
    return file_name.endswith(".dart") and not file_name.endswith("g.dart")

def merge_dart_files():
    with open(OUTPUT_FILE, "w", encoding="utf-8") as outfile:
        for root, dirs, files in os.walk(SOURCE_DIR):
            for file in files:
                if should_include(file):
                    file_path = os.path.join(root, file)
                    with open(file_path, "r", encoding="utf-8") as infile:
                        outfile.write(f"// ----- FILE: {file_path} -----\n")
                        outfile.write(infile.read())
                        outfile.write("\n\n")
    print("Archivo combinado creado:", OUTPUT_FILE)

if __name__ == "__main__":
    merge_dart_files()
