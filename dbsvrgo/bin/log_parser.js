const fs = require('fs');
const readline = require('readline');

// 创建一个可读流
const fileStream = fs.createReadStream('./log/dbsvrgo.log');

// 使用 readline 接口逐行读取文件
const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
});

let lineCounter = 0;
rl.on('line', (line) => {
    lineCounter++;
    try {
        // 解析每一行JSON数据
        const logEntry = JSON.parse(line);
        console.log(logEntry);
    } catch (err) {
        console.error("解析错误：", err);
    }
});

rl.on('close', () => {
    console.log("文件读取完毕");
});
