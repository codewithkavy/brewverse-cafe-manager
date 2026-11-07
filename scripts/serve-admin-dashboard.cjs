const http=require('node:http');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'../super_admin_dashboard/build/web');
if(!fs.existsSync(path.join(root,'index.html')))throw new Error('Build the dashboard before starting preview.');
const types={'.html':'text/html','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.png':'image/png','.svg':'image/svg+xml','.ttf':'font/ttf','.woff2':'font/woff2','.css':'text/css','.ico':'image/x-icon'};
http.createServer((req,res)=>{
 try{
  const url=new URL(req.url,'http://127.0.0.1');
  const file=path.resolve(root,'.'+decodeURIComponent(url.pathname==='/'?'/index.html':url.pathname));
  if(!file.startsWith(root+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);res.end('Not found');return;}
  res.writeHead(200,{'Content-Type':types[path.extname(file)]??'application/octet-stream','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'});
  fs.createReadStream(file).pipe(res);
 }catch{res.writeHead(400);res.end('Bad request');}
}).listen(8767,'127.0.0.1',()=>console.log('BrewVerse Super Admin: http://127.0.0.1:8767 (loopback only)'));
