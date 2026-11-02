// fs/path/vm: 读取本地TeX运行时、工程文件和加载其脚本。
const fs = require('fs');
const path = require('path');
const vm = require('vm');
// runtime/root/status: TensorWriting附带的离线编译器、报告目录和简短进度输出。
const runtime = process.env.AFDX_TEX_RUNTIME || 'C:/DEVELOP/TensorWriting/texlive/installed/99c37a25e7711969-staging-OrDrxo';
const root = __dirname;
const status = text => process.stdout.write(String(text) + '\n'); // text: 一条编译进度。
global.self = globalThis;
global.require = require;
global.busytex = require(path.join(runtime, 'busytex.js'));
global.fetch = async source => { // source: 运行时自带的数据或WASM文件。
  const bytes = fs.readFileSync(String(source)); // bytes: 本地运行时资源。
  return new Response(bytes, {headers: {'Content-Type': String(source).endsWith('.wasm') ? 'application/wasm' : 'text/javascript'}});
};
console.log = () => {};
vm.runInThisContext(fs.readFileSync(path.join(runtime, 'busytex_pipeline.js'), 'utf8'));
// loader/files/collect: 本地包加载器、送入编译器的TeX文件及按目录收集文件的函数。
const loader = async source => { // source: 编译器或TeX资源包脚本。
  if (!source.endsWith('busytex.js')) vm.runInThisContext(fs.readFileSync(source, 'utf8'));
};
const files = [];
function collect(folder) { // folder: 当前报告子目录。
  for (const entry of fs.readdirSync(folder, {withFileTypes: true})) { // entry: 当前目录项。
    const full = path.join(folder, entry.name); // full: 当前文件或目录的绝对路径。
    if (entry.isDirectory() && entry.name === 'chapters') collect(full);
    else if (entry.isFile() && entry.name.endsWith('.tex')) files.push({path: path.relative(root, full).replaceAll('\\', '/'), contents: fs.readFileSync(full)});
  }
}
collect(root);
(async () => {
  // data/pipeline/result: 本地TeX资源包、编译流水线和最终结果。
  const data = path.join(runtime, 'texlive.js');
  const pipeline = new BusytexPipeline(path.join(runtime, 'busytex.js'), path.join(runtime, 'busytex.wasm'), [data], [data], [], () => {}, () => status('Offline TeX initialized'), true, loader);
  await pipeline.on_initialized_promise;
  status('Compiling ' + files.length + ' TeX files');
  const result = await pipeline.compile(files, 'main.tex', false, false, false, true, 'silent', 'xetex_bibtex8_dvipdfmx', [data]);
  fs.writeFileSync(path.join(root, 'main.build.log'), result.log);
  if (result.exit_code || !result.pdf || result.logs.some(entry => /^!/m.test(entry.log || ''))) throw new Error('TeX failed; see main.build.log'); // entry: 每次TeX运行的实际日志。
  fs.writeFileSync(path.join(root, 'main.pdf'), result.pdf);
  status('PDF saved: ' + result.pdf.length + ' bytes');
})().catch(error => { process.stderr.write(String(error.stack || error) + '\n'); process.exitCode = 1; }); // error: 本次编译异常。
