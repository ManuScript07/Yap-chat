import {createServer} from 'node:http';
import {randomBytes, timingSafeEqual} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {PaginationLab} from './lab.mjs';

const commands = ['seed','status','prepare','verify','serve','cleanup','action'];
const args = process.argv.slice(2);
const command = args[0] || 'status';
const named = key => { const i=args.indexOf(key); return i<0?undefined:args[i+1]; };
if (args.includes('--help')) {
  console.log('node tools/pagination_lab/main.mjs seed|status|prepare|verify|serve|cleanup|action <name> [--name manual]');
  process.exit(0);
}
if (!commands.includes(command)) throw Error('Unknown lab command');
const lab = new PaginationLab(named('--name') || 'manual').connect();
try {
  if (command === 'serve') {
    lab.requireSeed();
    const port = Number(named('--port') || 8743);
    if (!Number.isInteger(port) || port<1024 || port>65535) throw Error('Invalid panel port');
    const origin=`http://127.0.0.1:${port}`;
    const token=randomBytes(32).toString('hex');
    const page=readFileSync(fileURLToPath(new URL('./panel.html',import.meta.url)),'utf8').replace('__LAB_CSRF__',token);
    let busy=false;
    const server=createServer(async (req,res)=>{
      res.setHeader('Cache-Control','no-store');
      res.setHeader('X-Content-Type-Options','nosniff');
      res.setHeader('Content-Security-Policy',"default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'");
      const json=(status,value)=>{res.writeHead(status,{'Content-Type':'application/json; charset=utf-8'});res.end(JSON.stringify(value));};
      if(req.headers.host!==`127.0.0.1:${port}`) return json(403,{error:'Loopback host required'});
      if(req.method==='GET'&&req.url==='/') {res.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});return res.end(page);}
      if(req.method==='GET'&&req.url==='/state') {
        try{return json(200,lab.status());}catch(error){return json(503,{error:error.message});}
      }
      if(req.method!=='POST'||req.url!=='/action') return json(404,{error:'Not found'});
      const supplied=Buffer.from(String(req.headers['x-pagination-lab-token']||''));
      if(req.headers.origin!==origin || req.headers['content-type']!=='application/json' || supplied.length!==token.length || !timingSafeEqual(supplied,Buffer.from(token))) {
        return json(403,{error:'Local panel action rejected'});
      }
      if(busy) return json(409,{error:'Дождитесь завершения предыдущего действия'});
      busy=true;
      try {
        let size=0;const chunks=[];
        for await(const chunk of req){size+=chunk.length;if(size>1024)throw Error('Request too large');chunks.push(chunk);}
        const {action}=JSON.parse(Buffer.concat(chunks).toString());
        if(typeof action!=='string')throw Error('Invalid action');
        const result=await lab.action(action);
        json(200,{result,state:lab.status()});
      }catch(error){json(400,{error:error.message});}finally{busy=false;}
    });
    server.listen(port,'127.0.0.1',()=>console.log(`Панель сценариев: ${origin}`));
    server.on('error',error=>{console.error(error.message);process.exitCode=1;});
    process.on('SIGINT',()=>server.close());
    process.on('SIGTERM',()=>server.close());
  } else {
    const result=command==='action'?await lab.action(args[1]):await lab[command]();
    console.log(JSON.stringify(result,null,2));
  }
}catch(error){console.error(error.message);process.exitCode=1;}
