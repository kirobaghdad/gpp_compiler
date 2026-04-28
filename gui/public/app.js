document.addEventListener('DOMContentLoaded', () => {
    const compileBtn = document.getElementById('compileBtn');
    const fileUpload = document.getElementById('fileUpload');
    const codeEditor = document.getElementById('codeEditor');
    const fileNameBadge = document.getElementById('fileNameBadge');
    const mainLayout = document.querySelector('.main-layout');
    const editorPane = document.querySelector('.editor-pane');
    const resultsPane = document.querySelector('.results-pane');
    const splitter = document.getElementById('splitter');
    const tabBtns = document.querySelectorAll('.tab-btn');
    const tabPanels = document.querySelectorAll('.tab-panel');
    const errorBadge = document.getElementById('errorBadge');

    // Default code to start playing with
    codeEditor.value = `int main() {
    int x = 5;
    float y = 3.14;
    return 0;
}`;

    // Enable actual Tab indentation inside the text editor
    codeEditor.addEventListener('keydown', function(e) {
        if (e.key === 'Tab') {
            e.preventDefault();
            const start = this.selectionStart;
            const end = this.selectionEnd;

            // Insert 4 spaces at cursor
            this.value = this.value.substring(0, start) + "    " + this.value.substring(end);

            // Move cursor directly after the spaces
            this.selectionStart = this.selectionEnd = start + 4;
            updateLineNumbers(); // explicitly update since 'input' event might not fire on preventDefault
        }
    });

    const lineNumbers = document.getElementById('lineNumbers');

    function updateLineNumbers() {
        const lineCount = codeEditor.value.split('\n').length;
        // Generate a string with numbers from 1 to lineCount
        lineNumbers.innerText = Array(lineCount).fill(0).map((_, i) => i + 1).join('\n');
    }

    codeEditor.addEventListener('input', updateLineNumbers);

    // Sync scrolling exactly
    codeEditor.addEventListener('scroll', () => {
        lineNumbers.scrollTop = codeEditor.scrollTop;
    });

    // Initial render
    updateLineNumbers();

    fileUpload.addEventListener('change', () => {
        const file = fileUpload.files[0];
        if (!file) return;

        const reader = new FileReader();
        reader.onload = () => {
            codeEditor.value = reader.result;
            fileNameBadge.textContent = file.name;
            updateLineNumbers();
        };
        reader.readAsText(file);
    });

    splitter.addEventListener('mousedown', () => {
        document.body.classList.add('resizing');
    });

    document.addEventListener('mousemove', (event) => {
        if (!document.body.classList.contains('resizing')) return;

        const bounds = mainLayout.getBoundingClientRect();
        const minPaneWidth = 320;
        const splitterWidth = splitter.offsetWidth;
        const maxLeftWidth = bounds.width - minPaneWidth - splitterWidth;
        const leftWidth = Math.min(
            Math.max(event.clientX - bounds.left, minPaneWidth),
            maxLeftWidth
        );

        editorPane.style.flex = `0 0 ${leftWidth}px`;
        resultsPane.style.flex = '1 1 auto';
    });

    document.addEventListener('mouseup', () => {
        document.body.classList.remove('resizing');
    });

    // Tab Switching Logic
    tabBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            // Remove active from all
            tabBtns.forEach(b => b.classList.remove('active'));
            tabPanels.forEach(p => p.classList.remove('active'));

            // Add active to clicked
            btn.classList.add('active');
            const targetId = `tab-${btn.dataset.tab}`;
            document.getElementById(targetId).classList.add('active');
        });
    });

    // Compile Button Logic
    compileBtn.addEventListener('click', async () => {
        const code = codeEditor.value;
        if (!code.trim()) return;

        // UI Loading state
        const btnText = compileBtn.querySelector('.btn-text');
        const loader = compileBtn.querySelector('.loader');
        
        btnText.textContent = "Compiling...";
        loader.classList.remove('hidden');
        compileBtn.disabled = true;

        try {
            const response = await fetch('http://localhost:3000/api/compile', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ code })
            });

            const data = await response.json();
            renderResults(data);

        } catch (error) {
            console.error("Compilation error:", error);
            alert("Failed to connect to the compilation server.");
        } finally {
            btnText.textContent = "Compile & Run";
            loader.classList.add('hidden');
            compileBtn.disabled = false;
        }
    });

    function renderResults(data) {
        // Render Quadruples
        const quadTab = document.getElementById('tab-quadruples');
        const quadTable = document.getElementById('quadTable').querySelector('tbody');
        quadTab.querySelector('.empty-state').classList.add('hidden');
        quadTab.querySelector('.table-container').classList.remove('hidden');
        quadTable.innerHTML = '';

        if (data.quadruples) {
            // Parse quadruples string like: (ASSIGN, 5, -, x)
            const lines = data.quadruples.split('\n');
            lines.forEach(line => {
                line = line.trim();
                if (line.startsWith('(') && line.endsWith(')')) {
                    const inner = line.substring(1, line.length - 1);
                    const parts = inner.split(',').map(s => s.trim());
                    if (parts.length >= 4) {
                        const tr = document.createElement('tr');
                        tr.innerHTML = `
                            <td class="op-cell">${parts[0]}</td>
                            <td>${parts[1]}</td>
                            <td>${parts[2]}</td>
                            <td>${parts[3]}</td>
                        `;
                        quadTable.appendChild(tr);
                    }
                }
            });
        }

        if (quadTable.innerHTML === '') {
            quadTable.innerHTML = '<tr><td colspan="4" style="text-align: center; color: var(--text-muted)">No quadruples generated.</td></tr>';
        }

        // Render Symbol Table
        const symTab = document.getElementById('tab-symbolTable');
        const symTable = document.getElementById('symTable').querySelector('tbody');
        symTab.querySelector('.empty-state').classList.add('hidden');
        symTab.querySelector('.table-container').classList.remove('hidden');
        symTable.innerHTML = '';

        const symbolRows = parseSymbolTable(data.symbolTable || '');
        symbolRows.forEach(row => {
            const tr = document.createElement('tr');
            row.forEach(value => {
                const td = document.createElement('td');
                td.textContent = value;
                tr.appendChild(td);
            });
            symTable.appendChild(tr);
        });

        if (symTable.innerHTML === '') {
            symTable.innerHTML = '<tr><td colspan="10" style="text-align: center; color: var(--text-muted)">Symbol table is empty.</td></tr>';
        }

        // Render Errors
        const errTab = document.getElementById('tab-errors');
        const errList = document.getElementById('errorsList');
        const totalErrors = data.syntaxErrors.length + data.semanticErrors.length;
        
        if (totalErrors > 0) {
            errorBadge.textContent = totalErrors;
            errorBadge.classList.remove('hidden');
            errTab.querySelector('.empty-state').classList.add('hidden');
            errList.classList.remove('hidden');
            errList.innerHTML = '';

            data.syntaxErrors.forEach(err => {
                const el = document.createElement('div');
                el.className = 'error-item syntax';
                el.textContent = err;
                errList.appendChild(el);
            });

            data.semanticErrors.forEach(err => {
                const el = document.createElement('div');
                el.className = 'error-item semantic';
                el.textContent = err;
                errList.appendChild(el);
            });

            // Automatically switch to errors tab if there are errors
            document.querySelector('.tab-btn[data-tab="errors"]').click();

        } else {
            errorBadge.classList.add('hidden');
            errTab.querySelector('.empty-state').classList.remove('hidden');
            errList.classList.add('hidden');
            
            // Auto switch to quadruples if it was a successful build
            document.querySelector('.tab-btn[data-tab="quadruples"]').click();
        }
    }

    function parseSymbolTable(symbolTable) {
        return symbolTable
            .split('\n')
            .map(line => line.trim())
            .filter(line => line && !line.startsWith('ID ') && !line.startsWith('-----'))
            .map(line => {
                const parts = line.split(/\s+/);
                if (parts.length < 9) return null;

                return [
                    parts[0],
                    parts[1],
                    parts[2],
                    parts[3],
                    parts[4],
                    parts[5],
                    parts[6],
                    parts[7],
                    parts[8],
                    parts.slice(9).join(' ') || '-'
                ];
            })
            .filter(Boolean);
    }
});
