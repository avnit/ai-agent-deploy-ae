import json

file_path = '/home/abambah/ai-agent-deploy-ae/colabs/MA_with_CR_and_CD_New.ipynb'

with open(file_path, 'r') as f:
    notebook = json.load(f)

for cell in notebook['cells']:
    if cell['cell_type'] == 'code':
        new_source = []
        for line in cell['source']:
            # Replace !pip with %pip, but keep the rest of the line intact
            # We handle lines that might be commented out too if they start with !pip
            # The user request specifically mentioned !pip -> %pip
            # The file content showed: "!pip install ...\n" and "# !pip install ...\n"
            
            # Simple replacement should work for "!pip" -> "%pip"
            # But we should be careful not to replace something like "print('!pip')"
            # Given the context, a simple replace on the start of the string or generally replacing "!pip install" with "%pip install" is safe enough for this notebook.
            
            if '!pip install' in line:
                line = line.replace('!pip install', '%pip install')
            new_source.append(line)
        cell['source'] = new_source

with open(file_path, 'w') as f:
    json.dump(notebook, f, indent=2) # indent=2 matches the file format I saw earlier roughly

print("Notebook updated successfully.")
