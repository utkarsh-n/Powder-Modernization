#!/usr/bin/env python3
"""Create a source-only release with reproducible validation evidence, without build caches."""
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[2]
output = root / 'Builds' / 'Powder-native-v0.6.2-source.zip'
excluded = {'.git', '.build', 'node_modules', '.swiftpm', 'xcuserdata'}
count = 0
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for folder in ('Native', 'docs', 'evidence', 'design'):
        base = root / folder
        if not base.exists():
            continue
        for path in sorted(base.rglob('*')):
            if not path.is_file() or path.is_symlink():
                continue
            relative = path.relative_to(root)
            if excluded.intersection(relative.parts) or any(part.startswith('DerivedData') for part in relative.parts):
                continue
            if path.name == '.DS_Store' or path.suffix in {'.air', '.metallib'}:
                continue
            archive.write(path, Path('Powder-native-v0.6.2') / relative)
            count += 1
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    names = archive.namelist()
    assert not any('DerivedData' in name for name in names)
    for required in ('Native/App/SimulationWorker.swift', 'Native/Tests/PlaygroundSessionTests.swift',
                     'Native/project.yml', 'Native/LICENSE', 'docs/Mac-v5.md', 'docs/Rendering-v5.md',
                     'Native/App/Intelligence/ScenePromptBar.swift', 'docs/Prompt-Bar-v5.1.md',
                     'Native/App/Design/MaterialSymbolCatalog.swift', 'docs/Material-Symbols-v5.2.md',
                     'Native/App/Intelligence/SceneConversationPanel.swift', 'Native/Tests/SceneIntelligenceTests.swift',
                     'docs/Intelligence-v6.md', 'docs/Community-References-v6.md',
                     'Native/App/AppIcon.icon/icon.json', 'Native/App/AppIcon.icon/Assets/PowderChamber.png',
                     'docs/App-Icon-v6.1.md', 'design/app-icon-v6.1/generation-prompt.md',
                     'Native/App/Intelligence/LocalSceneAssistant.swift',
                     'Native/App/Intelligence/ResilientSceneAssistant.swift', 'docs/Intelligence-v6.2.md'):
        assert 'Powder-native-v0.6.2/' + required in names, required
print(f'{count} files; {output.stat().st_size:,} bytes; ZIP integrity passed')
