#!/usr/bin/env node
/**
 * MapScanner Data Converter
 * 
 * Converts MapScanner JSON output (heightmap + mesh chunks) into
 * optimized formats for the WebUI:
 * 
 * 1. GLB (binary glTF) — full 3D mesh with normals, chunked LOD
 * 2. Heightmap PNG — grayscale heightmap image
 * 3. Compressed JSON — optimized vertex/index buffers
 * 
 * Usage:
 *   node convert-scan.js <input-dir> [--format glb|json|png] [--output <dir>]
 *   node convert-scan.js heightmap.json --format png
 *   node convert-scan.js scan-data/ --format glb --output ./output/
 */

const fs = require('fs');
const path = require('path');

// ============================================================================
// Heightmap to Three.js PlaneGeometry data
// ============================================================================

function convertHeightmap(heightmapData) {
    const { mapId, mapName, gridSpacing, originX, originZ, gridW, gridH, heights } = heightmapData;
    
    console.log(`Converting heightmap: ${mapName} (${mapId})`);
    console.log(`  Grid: ${gridW} x ${gridH} @ ${gridSpacing}m spacing`);
    console.log(`  Origin: (${originX}, ${originZ})`);
    
    // Build vertex positions and normals
    const positions = [];
    const normals = [];
    const uvs = [];
    const indices = [];
    const NO_DATA = -9999;
    
    let minY = Infinity, maxY = -Infinity;
    let validVertices = 0;
    
    // Vertex map to track which grid cells have valid data
    const vertexMap = new Map(); // "row_col" -> vertex index
    
    for (let row = 0; row < gridH; row++) {
        for (let col = 0; col < gridW; col++) {
            const y = heights[row][col];
            if (y === NO_DATA) continue;
            
            const x = originX + col * gridSpacing;
            const z = originZ + row * gridSpacing;
            
            const vertIdx = validVertices;
            vertexMap.set(`${row}_${col}`, vertIdx);
            
            positions.push(x, y, z);
            
            // Calculate normals from height differences
            const yLeft  = col > 0 && heights[row][col-1] !== NO_DATA ? heights[row][col-1] : y;
            const yRight = col < gridW-1 && heights[row][col+1] !== NO_DATA ? heights[row][col+1] : y;
            const yUp    = row > 0 && heights[row-1][col] !== NO_DATA ? heights[row-1][col] : y;
            const yDown  = row < gridH-1 && heights[row+1][col] !== NO_DATA ? heights[row+1][col] : y;
            
            const nx = (yLeft - yRight) / (2 * gridSpacing);
            const nz = (yUp - yDown) / (2 * gridSpacing);
            const ny = 1.0;
            const len = Math.sqrt(nx*nx + ny*ny + nz*nz);
            normals.push(nx/len, ny/len, nz/len);
            
            // UV coordinates (0-1 range)
            uvs.push(col / (gridW - 1), row / (gridH - 1));
            
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
            
            validVertices++;
        }
    }
    
    // Build triangle indices
    for (let row = 0; row < gridH - 1; row++) {
        for (let col = 0; col < gridW - 1; col++) {
            const v00 = vertexMap.get(`${row}_${col}`);
            const v10 = vertexMap.get(`${row}_${col+1}`);
            const v01 = vertexMap.get(`${row+1}_${col}`);
            const v11 = vertexMap.get(`${row+1}_${col+1}`);
            
            if (v00 !== undefined && v10 !== undefined && v01 !== undefined && v11 !== undefined) {
                indices.push(v00, v10, v01);
                indices.push(v10, v11, v01);
            } else if (v00 !== undefined && v10 !== undefined && v01 !== undefined) {
                indices.push(v00, v10, v01);
            } else if (v10 !== undefined && v11 !== undefined && v01 !== undefined) {
                indices.push(v10, v11, v01);
            }
        }
    }
    
    console.log(`  Vertices: ${validVertices}, Triangles: ${indices.length / 3}`);
    console.log(`  Height range: ${minY.toFixed(1)} to ${maxY.toFixed(1)}`);
    
    return {
        mapId,
        mapName,
        gridSpacing,
        originX,
        originZ,
        gridW,
        gridH,
        minY,
        maxY,
        vertexCount: validVertices,
        triangleCount: indices.length / 3,
        positions: new Float32Array(positions),
        normals: new Float32Array(normals),
        uvs: new Float32Array(uvs),
        indices: validVertices > 65535 ? new Uint32Array(indices) : new Uint16Array(indices),
    };
}

// ============================================================================
// Convert mesh chunks to combined geometry
// ============================================================================

function convertChunks(chunks) {
    const allPositions = [];
    const allNormals = [];
    const allIndices = [];
    let vertexOffset = 0;
    
    for (const chunk of chunks) {
        const { vertices, indices, vertexCount } = chunk;
        
        // Vertices are flat: x,y,z, nx,ny,nz per vertex
        for (let i = 0; i < vertices.length; i += 6) {
            allPositions.push(vertices[i], vertices[i+1], vertices[i+2]);
            allNormals.push(vertices[i+3], vertices[i+4], vertices[i+5]);
        }
        
        // Offset indices
        for (const idx of indices) {
            allIndices.push(idx + vertexOffset);
        }
        
        vertexOffset += vertexCount;
    }
    
    console.log(`Combined chunks: ${chunks.length} chunks -> ${vertexOffset} vertices, ${allIndices.length / 3} triangles`);
    
    return {
        vertexCount: vertexOffset,
        triangleCount: allIndices.length / 3,
        positions: new Float32Array(allPositions),
        normals: new Float32Array(allNormals),
        indices: vertexOffset > 65535 ? new Uint32Array(allIndices) : new Uint16Array(allIndices),
    };
}

// ============================================================================
// Generate binary glTF (GLB)
// ============================================================================

function toGLB(geometry, mapId, mapName) {
    const { positions, normals, indices, vertexCount, triangleCount } = geometry;
    
    // Build buffer views and accessors
    const posBuffer = Buffer.from(positions.buffer);
    const normalBuffer = Buffer.from(normals.buffer);
    const indexBuffer = Buffer.from(indices.buffer);
    
    // Align buffers to 4-byte boundaries
    const pad4 = (b) => {
        const rem = b.length % 4;
        return rem === 0 ? b : Buffer.concat([b, Buffer.alloc(4 - rem)]);
    };
    
    const paddedPos = pad4(posBuffer);
    const paddedNorm = pad4(normalBuffer);
    const paddedIdx = pad4(indexBuffer);
    
    const binBuffer = Buffer.concat([paddedPos, paddedNorm, paddedIdx]);
    
    // Calculate bounding box
    let minPos = [Infinity, Infinity, Infinity];
    let maxPos = [-Infinity, -Infinity, -Infinity];
    for (let i = 0; i < positions.length; i += 3) {
        for (let j = 0; j < 3; j++) {
            if (positions[i+j] < minPos[j]) minPos[j] = positions[i+j];
            if (positions[i+j] > maxPos[j]) maxPos[j] = positions[i+j];
        }
    }
    
    const isUint32 = indices instanceof Uint32Array;
    
    const gltf = {
        asset: { version: "2.0", generator: "MapScanner Converter" },
        scene: 0,
        scenes: [{ name: mapName || mapId, nodes: [0] }],
        nodes: [{ name: mapId, mesh: 0 }],
        meshes: [{
            name: `${mapId}_terrain`,
            primitives: [{
                attributes: { POSITION: 0, NORMAL: 1 },
                indices: 2,
                mode: 4 // TRIANGLES
            }]
        }],
        accessors: [
            {
                bufferView: 0,
                componentType: 5126, // FLOAT
                count: vertexCount,
                type: "VEC3",
                min: minPos,
                max: maxPos
            },
            {
                bufferView: 1,
                componentType: 5126,
                count: vertexCount,
                type: "VEC3"
            },
            {
                bufferView: 2,
                componentType: isUint32 ? 5125 : 5123, // UINT32 or UINT16
                count: indices.length,
                type: "SCALAR"
            }
        ],
        bufferViews: [
            { buffer: 0, byteOffset: 0, byteLength: posBuffer.length, target: 34962 },
            { buffer: 0, byteOffset: paddedPos.length, byteLength: normalBuffer.length, target: 34962 },
            { buffer: 0, byteOffset: paddedPos.length + paddedNorm.length, byteLength: indexBuffer.length, target: 34963 }
        ],
        buffers: [{ byteLength: binBuffer.length }]
    };
    
    const jsonStr = JSON.stringify(gltf);
    const jsonBuffer = Buffer.from(jsonStr);
    const jsonPadded = pad4(Buffer.concat([jsonBuffer, Buffer.alloc((4 - jsonBuffer.length % 4) % 4, 0x20)]));
    
    // GLB header: magic(4) + version(4) + length(4) = 12 bytes
    // JSON chunk: length(4) + type(4) + data
    // BIN chunk:  length(4) + type(4) + data
    const totalLength = 12 + 8 + jsonPadded.length + 8 + binBuffer.length;
    
    const glb = Buffer.alloc(totalLength);
    let offset = 0;
    
    // Header
    glb.writeUInt32LE(0x46546C67, offset); offset += 4; // magic "glTF"
    glb.writeUInt32LE(2, offset); offset += 4;           // version
    glb.writeUInt32LE(totalLength, offset); offset += 4; // total length
    
    // JSON chunk
    glb.writeUInt32LE(jsonPadded.length, offset); offset += 4;
    glb.writeUInt32LE(0x4E4F534A, offset); offset += 4; // "JSON"
    jsonPadded.copy(glb, offset); offset += jsonPadded.length;
    
    // BIN chunk
    glb.writeUInt32LE(binBuffer.length, offset); offset += 4;
    glb.writeUInt32LE(0x004E4942, offset); offset += 4; // "BIN\0"
    binBuffer.copy(glb, offset);
    
    return glb;
}

// ============================================================================
// Generate heightmap PNG (grayscale 16-bit)
// ============================================================================

function toHeightmapPNG(heightmapData) {
    // Simple uncompressed PGM format (can be converted to PNG with external tools)
    const { gridW, gridH, heights, minY, maxY } = heightmapData;
    const NO_DATA = -9999;
    const range = maxY - minY || 1;
    
    // 16-bit grayscale PGM
    let pgm = `P5\n# MapScanner heightmap: ${heightmapData.mapId}\n${gridW} ${gridH}\n65535\n`;
    const headerBuf = Buffer.from(pgm, 'ascii');
    const pixelBuf = Buffer.alloc(gridW * gridH * 2);
    
    for (let row = 0; row < gridH; row++) {
        for (let col = 0; col < gridW; col++) {
            const y = heights[row][col];
            const idx = (row * gridW + col) * 2;
            if (y === NO_DATA) {
                pixelBuf.writeUInt16BE(0, idx);
            } else {
                const normalized = Math.max(0, Math.min(65535, Math.floor(((y - minY) / range) * 65535)));
                pixelBuf.writeUInt16BE(normalized, idx);
            }
        }
    }
    
    return Buffer.concat([headerBuf, pixelBuf]);
}

// ============================================================================
// Generate optimized JSON for WebUI direct loading
// ============================================================================

function toOptimizedJSON(geometry, heightmapData) {
    return JSON.stringify({
        format: 'mapscanner-v1',
        mapId: heightmapData?.mapId || 'unknown',
        mapName: heightmapData?.mapName || 'Unknown',
        gridSpacing: heightmapData?.gridSpacing || 1,
        bounds: {
            minX: heightmapData?.originX || 0,
            minZ: heightmapData?.originZ || 0,
            maxX: (heightmapData?.originX || 0) + (heightmapData?.gridW || 0) * (heightmapData?.gridSpacing || 1),
            maxZ: (heightmapData?.originZ || 0) + (heightmapData?.gridH || 0) * (heightmapData?.gridSpacing || 1),
            minY: heightmapData?.minY || 0,
            maxY: heightmapData?.maxY || 100,
        },
        mesh: {
            vertexCount: geometry.vertexCount,
            triangleCount: geometry.triangleCount,
            // Base64 encode binary buffers for compact JSON
            positions: Buffer.from(geometry.positions.buffer).toString('base64'),
            normals: Buffer.from(geometry.normals.buffer).toString('base64'),
            indices: Buffer.from(geometry.indices.buffer).toString('base64'),
            indexType: geometry.indices instanceof Uint32Array ? 'uint32' : 'uint16',
        },
    });
}

// ============================================================================
// Main
// ============================================================================

function main() {
    const args = process.argv.slice(2);
    
    if (args.length === 0) {
        console.log('MapScanner Data Converter');
        console.log('========================');
        console.log('');
        console.log('Usage:');
        console.log('  node convert-scan.js <heightmap.json> [options]');
        console.log('  node convert-scan.js <scan-dir/> [options]');
        console.log('');
        console.log('Options:');
        console.log('  --format <glb|json|png|all>  Output format (default: all)');
        console.log('  --output <dir>               Output directory (default: ./output/)');
        console.log('');
        console.log('Input can be:');
        console.log('  - A single heightmap JSON file');
        console.log('  - A directory containing heightmap.json and chunk_*.json files');
        process.exit(0);
    }
    
    const inputPath = args[0];
    let format = 'all';
    let outputDir = './output';
    
    for (let i = 1; i < args.length; i++) {
        if (args[i] === '--format' && args[i+1]) {
            format = args[i+1];
            i++;
        } else if (args[i] === '--output' && args[i+1]) {
            outputDir = args[i+1];
            i++;
        }
    }
    
    // Ensure output directory exists
    if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
    }
    
    let heightmapData = null;
    let chunks = [];
    
    const stat = fs.statSync(inputPath);
    
    if (stat.isDirectory()) {
        // Load all files from directory
        const files = fs.readdirSync(inputPath);
        
        for (const file of files) {
            const filePath = path.join(inputPath, file);
            if (file === 'heightmap.json' || file.startsWith('heightmap')) {
                console.log(`Loading heightmap: ${file}`);
                heightmapData = JSON.parse(fs.readFileSync(filePath, 'utf8'));
            } else if (file.startsWith('chunk_') && file.endsWith('.json')) {
                console.log(`Loading chunk: ${file}`);
                chunks.push(JSON.parse(fs.readFileSync(filePath, 'utf8')));
            }
        }
    } else {
        // Single file
        const data = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
        if (data.type === 'heightmap' || data.heights) {
            heightmapData = data;
        } else if (data.vertices) {
            chunks.push(data);
        }
    }
    
    if (!heightmapData && chunks.length === 0) {
        console.error('No valid scan data found');
        process.exit(1);
    }
    
    const mapId = heightmapData?.mapId || chunks[0]?.mapId || 'unknown';
    const mapName = heightmapData?.mapName || chunks[0]?.mapName || 'Unknown';
    
    console.log(`\nProcessing map: ${mapName} (${mapId})`);
    
    // Convert heightmap
    let heightmapGeometry = null;
    if (heightmapData) {
        heightmapGeometry = convertHeightmap(heightmapData);
    }
    
    // Convert chunks
    let chunkGeometry = null;
    if (chunks.length > 0) {
        chunkGeometry = convertChunks(chunks);
    }
    
    // Primary geometry: prefer chunks (higher detail), fallback to heightmap
    const primaryGeometry = chunkGeometry || heightmapGeometry;
    
    if (!primaryGeometry) {
        console.error('No geometry could be generated');
        process.exit(1);
    }
    
    // Output
    if (format === 'glb' || format === 'all') {
        const glb = toGLB(primaryGeometry, mapId, mapName);
        const glbPath = path.join(outputDir, `${mapId}.glb`);
        fs.writeFileSync(glbPath, glb);
        console.log(`\nWritten GLB: ${glbPath} (${(glb.length / 1024 / 1024).toFixed(1)} MB)`);
    }
    
    if (format === 'json' || format === 'all') {
        const json = toOptimizedJSON(primaryGeometry, heightmapData);
        const jsonPath = path.join(outputDir, `${mapId}.json`);
        fs.writeFileSync(jsonPath, json);
        console.log(`Written JSON: ${jsonPath} (${(json.length / 1024 / 1024).toFixed(1)} MB)`);
    }
    
    if ((format === 'png' || format === 'all') && heightmapData) {
        // Heights array for PNG needs min/max
        heightmapData.minY = heightmapGeometry.minY;
        heightmapData.maxY = heightmapGeometry.maxY;
        const pgm = toHeightmapPNG(heightmapData);
        const pgmPath = path.join(outputDir, `${mapId}_heightmap.pgm`);
        fs.writeFileSync(pgmPath, pgm);
        console.log(`Written heightmap PGM: ${pgmPath} (${(pgm.length / 1024).toFixed(0)} KB)`);
        console.log(`  Convert to PNG: ffmpeg -i ${pgmPath} ${mapId}_heightmap.png`);
    }
    
    // Also write heightmap as simple grid JSON for WebUI direct consumption
    if (heightmapData && (format === 'json' || format === 'all')) {
        const simpleHeightmap = {
            mapId,
            mapName,
            gridSpacing: heightmapData.gridSpacing,
            originX: heightmapData.originX,
            originZ: heightmapData.originZ,
            gridW: heightmapData.gridW,
            gridH: heightmapData.gridH,
            minY: heightmapGeometry.minY,
            maxY: heightmapGeometry.maxY,
            // Flatten heights for compact storage
            heightsFlat: heightmapData.heights.flat(),
        };
        const hmPath = path.join(outputDir, `${mapId}_heightmap.json`);
        fs.writeFileSync(hmPath, JSON.stringify(simpleHeightmap));
        console.log(`Written heightmap JSON: ${hmPath}`);
    }
    
    console.log('\nDone!');
}

main();
