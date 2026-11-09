const fs = require('fs');
const vm = require('vm');
const path = require('path');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const escape = text => String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
function element(type, props = {}, ...children) {
    props ||= {};
    children = children.length ? children : [props.children];
    if (typeof type === 'function') return type({...props, children: children.flat()});
    if (typeof type !== 'string') return children.flat().filter(Boolean).join('');
    const attrs = Object.entries(props).filter(([k,v]) => !['children','ref','key'].includes(k) && !k.startsWith('on') && v != null && v !== false).map(([k,v]) => {
        if (k === 'style') v = Object.entries(v).map(([a,b]) => `${a.replace(/[A-Z]/g, c=>'-'+c.toLowerCase())}:${b}`).join(';');
        k = ({className:'class', htmlFor:'for', defaultValue:'value', strokeWidth:'stroke-width', strokeLinecap:'stroke-linecap', strokeLinejoin:'stroke-linejoin'})[k] || k;
        return ` ${k}="${escape(v === true ? '' : v)}"`;
    }).join('');
    return `<${type}${attrs}>${children.flat(Infinity).filter(x=>x != null && x !== false).join('')}</${type}>`;
}
const React = {createElement:element, forwardRef:f=>p=>f(p,null), useState:x=>[x,()=>{}], useId:()=> 'reference', Fragment:Symbol()};
const context = {window:{React}};
vm.createContext(context);
vm.runInContext(read('_design/canvas/ds/chronoflow/components/bundle.js'), context);
const components = context.window.ChronoFlow;
function imports(html) {
    return html.replace(/<x-import\b([^>]*?)(?:\/>|>([\s\S]*?)<\/x-import>)/g, (_, attrs, child) => {
        const props = Object.fromEntries([...attrs.matchAll(/([\w-]+)="([^"]*)"/g)].map(x=>[x[1],x[2]]));
        const name = props['component-from-global-scope'].split('.').pop();
        delete props['component-from-global-scope'];
        if (props['default-value']) { props.defaultValue=props['default-value']; delete props['default-value']; }
        props.children = child || '';
        return components[name](props);
    });
}
let fonts = '';
for (const [family,weight,file] of [['Figtree',400,'CFFigtree-400.ttf'],['Figtree',500,'CFFigtree-500.ttf'],['Figtree',600,'CFFigtree-600.ttf'],['Fraunces',400,'CFFraunces-400-Opsz32.ttf']]) {
    fonts+=`@font-face{font-family:${family};font-weight:${weight};src:url(../../../Packages/ChronoFlowKit/Sources/DesignSystem/Resources/Fonts/${file})}`;
}
const css = read('_design/canvas/theme.css') + read('_design/canvas/ds/chronoflow/components/bundle.css') + fonts + 'body{margin:0}';
const errors={none:null,wrong:["That email and password don't match.",'Check both and try again, or reset your password.'],locked:['Too many attempts.','Wait a few minutes before you try again, or reset your password now.'],server:['Something went wrong on our side.','Try again in a moment.']};
const twoFactorSource = read('_design/canvas/AuthTwoFactor.dc.html');
const twoFactorContext = {DCLogic: class { constructor(props) { this.props = props; } }};
vm.createContext(twoFactorContext);
vm.runInContext(twoFactorSource.match(/<script type="text\/x-dc"[^>]*>([\s\S]*?)<\/script>/)[1] + '\nthis.Board = Component;', twoFactorContext);
function twoFactor(theme, recovery, state) {
    const board = new twoFactorContext.Board({theme, screen:'twofactor', error:state});
    board.state.recovery = recovery;
    const values = board.renderVals();
    const value = key => key.split('.').reduce((v,k)=>v[k], values);
    let html = twoFactorSource.split('</helmet>')[1].split('</x-dc>')[0];
    html = html.replace(/<div class="pattern-dots"[^>]*><\/div>/g,'');
    const condition = /<sc-if\b([^>]*)>((?:(?!<sc-if)[\s\S])*?)<\/sc-if>/g;
    while (html.includes('<sc-if')) {
        html = html.replace(condition, (_, attrs, body) => value(attrs.match(/value="\{\{([^}]+)\}\}"/)[1]) ? body : '');
    }
    if (state !== 'field') html = html.replace(/ default-value="482913" error="[^"]*"/,'');
    html = html.replace(/\s+on-[\w-]+="[^"]*"/g, '');
    return imports(html.replace(/\{\{([^}]+)\}\}/g, (_, key) => escape(value(key))));
}
function save(name,html) { fs.writeFileSync(path.join(root,'_design/frames/auth',name+'.html'),`<!doctype html><meta charset="utf-8"><style>${css}</style>${html}`.replace(/[ \t]+$/gm, '')); }
for (const theme of ['light','dark']) {
    for (const recovery of [false,true]) {
        for (const state of recovery ? ['none','attempts','server'] : ['none','field','attempts','server']) {
            save(`two-factor-${recovery?'recovery':'code'}-${state}-${theme}`,twoFactor(theme,recovery,state));
        }
    }
    for (const [state,error] of Object.entries(errors)) {
        let html=read('_design/canvas/AuthSignIn.dc.html').split('</helmet>')[1].split('</x-dc>')[0];
        html=html.replace(/<div class="pattern-dots"[^>]*><\/div>/g,'');
        html=html.replace(/<sc-if[^>]*>([\s\S]*?)<\/sc-if>/g,(_,s)=>error?s:'');
        html=html.replaceAll('{{theme}}',theme).replaceAll('{{err.title}}',error?.[0]||'').replaceAll('{{err.body}}',error?.[1]||'');
        save(`sign-in-${state}-${theme}`,imports(html));
    }
    let states=read('_design/canvas/AuthStates.dc.html').split('</helmet>')[1].split('</x-dc>')[0].replaceAll('{{theme}}',theme);
    save(`banners-${theme}`,states);
    save(`controls-${theme}`,`<div data-theme="${theme}" style="width:375px;padding:20px;background:var(--card);color:var(--card-foreground);display:grid;gap:14px;box-sizing:border-box;font-family:var(--font-sans)">${components.Field({label:'Email',id:'empty'})}${components.Field({label:'Email',id:'error',error:'Please fill this in.'})}${components.Field({label:'Password',id:'hint',hint:'At least 10 characters.'})}${components.Button({children:'Sign in',variant:'outline',size:'lg'})}${components.Button({children:'Sign in',size:'lg',loading:true})}${components.Button({children:'Sign in',size:'lg',disabled:true})}${components.Notice({title:'Check your inbox.',children:'If rick@example.com has an account, a link to choose a new password is on its way.'})}</div>`);
}
