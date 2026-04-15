const express = require('express');
const cors = require('cors');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

app.post('/api/compile', (req, res) => {
    const code = req.body.code || '';
    
    // Create temp file
    const tempFilePath = path.join(os.tmpdir(), `source_${Date.now()}.gpp`);
    
    fs.writeFile(tempFilePath, code, (err) => {
        if (err) {
            return res.status(500).json({ error: 'Failed to write temporary file' });
        }

        // Execute compiler
        const compilerPath = path.resolve(__dirname, '../gpp_compiler');
        
        exec(`"${compilerPath}" "${tempFilePath}"`, (error, stdout, stderr) => {
            // Compiler returns non-zero if there are errors, so we handle both stdout and stderr
            const combinedOutput = (stdout || '') + '\n' + (stderr || '');
            
            // Clean up temp file
            fs.unlink(tempFilePath, () => {});

            // Parsing output
            const result = {
                syntaxErrors: [],
                semanticErrors: [],
                quadruples: '',
                symbolTable: '',
                rawOutput: combinedOutput
            };

            // Parse syntax and semantic errors
            const syntaxRegex = /^Error at line .*$/gm;
            const semanticRegex = /^Semantic Error at line .*$/gm;
            
            let match;
            while ((match = syntaxRegex.exec(combinedOutput)) !== null) {
                result.syntaxErrors.push(match[0]);
            }
            while ((match = semanticRegex.exec(combinedOutput)) !== null) {
                result.semanticErrors.push(match[0]);
            }

            // Extract quadruples block
            const quadruplesStartToken = 'Quadruples\n';
            const symbolTableStartToken = 'Symbol Table\n';
            
            const quadStart = combinedOutput.indexOf(quadruplesStartToken);
            const symStart = combinedOutput.indexOf(symbolTableStartToken);
            
            if (quadStart !== -1 && symStart !== -1 && symStart > quadStart) {
                result.quadruples = combinedOutput.substring(quadStart + quadruplesStartToken.length, symStart).trim();
            }

            // Extract symbol table block
            if (symStart !== -1) {
                let symContent = combinedOutput.substring(symStart + symbolTableStartToken.length).trim();
                // Strip the final parsing success message if there
                symContent = symContent.replace('Parsing completed successfully.', '').trim();
                result.symbolTable = symContent;
            }

            res.json(result);
        });
    });
});

app.listen(PORT, () => {
    console.log(`GPP Compiler GUI running at http://localhost:${PORT}`);
});
