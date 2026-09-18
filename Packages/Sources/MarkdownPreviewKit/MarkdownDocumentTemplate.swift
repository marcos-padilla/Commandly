import Foundation

enum MarkdownDocumentTemplate {
    static func make(
        input: MarkdownRenderInput,
        configuration: MarkdownPreviewConfiguration,
        parsed: MarkdownParseResult
    ) -> String {
        let title = input.documentTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title?.isEmpty == false ? String(title?.prefix(200) ?? "") : "Markdown Preview"
        let frontMatter = configuration.rendersFrontMatter
            ? frontMatterHTML(parsed.frontMatter)
            : ""
        let contents = (input.emitsTableOfContents ?? configuration.showsTableOfContents)
            ? tableOfContentsHTML(parsed.outline)
            : ""
        let source = sourceHTML(
            input.sourceMarkdown ?? input.markdown,
            showsLineNumbers: configuration.showsLineNumbers
        )
        let renderedHidden = configuration.sourceViewMode == .source ? " hidden" : ""
        let sourceHidden = configuration.sourceViewMode == .rendered ? " hidden" : ""
        let themeClass = "theme-\(configuration.theme.rawValue)"
        let codeClass = "code-theme-\(configuration.codeTheme.rawValue)"
        let fontClass = "font-\(configuration.fontFamily.rawValue)"

        return """
        <!doctype html>
        <html lang="und" style="--preview-zoom:\(decimal(configuration.initialZoom));--font-size:\(decimal(configuration.fontSize))px;--line-height:\(decimal(configuration.lineHeight));--content-width:\(decimal(configuration.contentWidth))px;--tab-width:\(configuration.tabWidth)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=5">
        <meta name="referrer" content="no-referrer">
        <meta http-equiv="Content-Security-Policy" content="\(MarkdownHTML.escapeAttribute(MarkdownHTMLHooks.contentSecurityPolicy))">
        <title>\(MarkdownHTML.escapeText(resolvedTitle))</title>
        <style>\(styles)</style>
        </head>
        <body class="\(themeClass) \(codeClass) \(fontClass)" data-view="\(configuration.sourceViewMode.rawValue)">
        <div id="markdown-preview-shell">
        \(contents)
        <main id="\(MarkdownHTMLHooks.contentElementID)" data-preview-hook="content" dir="auto"\(renderedHidden)>
        \(frontMatter)
        \(parsed.bodyHTML)
        </main>
        <pre id="\(MarkdownHTMLHooks.sourceElementID)" data-preview-hook="source" tabindex="0" dir="auto"\(sourceHidden)>\(source)</pre>
        </div>
        <script nonce="\(MarkdownHTMLHooks.scriptNonce)">\(hooksScript)</script>
        </body>
        </html>
        """
    }

    private static func frontMatterHTML(_ entries: [MarkdownFrontMatterEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        let rows = entries.map { entry in
            let value = MarkdownHTML.escapeText(entry.value).replacingOccurrences(of: "\n", with: "<br>")
            return "<tr><th scope=\"row\">\(MarkdownHTML.escapeText(entry.key))</th><td>\(value)</td></tr>"
        }.joined()
        return "<details class=\"front-matter\" open><summary>Document metadata</summary><table><tbody>\(rows)</tbody></table></details>"
    }

    private static func tableOfContentsHTML(_ outline: [MarkdownOutlineEntry]) -> String {
        guard !outline.isEmpty else { return "" }
        let items = outline.map { entry in
            "<li class=\"toc-level-\(entry.level)\"><a href=\"#\(MarkdownHTML.escapeAttribute(entry.anchor))\" data-outline-anchor=\"\(MarkdownHTML.escapeAttribute(entry.anchor))\">\(MarkdownHTML.escapeText(entry.title))</a></li>"
        }.joined()
        return "<nav id=\"\(MarkdownHTMLHooks.tableOfContentsElementID)\" data-preview-hook=\"outline\" aria-label=\"Table of contents\"><div class=\"toc-title\">Contents</div><ol>\(items)</ol></nav>"
    }

    private static func sourceHTML(_ source: String, showsLineNumbers: Bool) -> String {
        guard showsLineNumbers else { return MarkdownHTML.escapeText(source) }
        return source.components(separatedBy: "\n").enumerated().map { offset, line in
            "<span class=\"source-line\" data-line=\"\(offset + 1)\"><span class=\"line-number\" aria-hidden=\"true\">\(offset + 1)</span><span class=\"line-content\">\(MarkdownHTML.escapeText(line))</span></span>"
        }.joined(separator: "\n")
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static let styles = #"""
    :root{color-scheme:light dark;--preview-zoom:1;--font-size:14px;--line-height:1.6;--content-width:860px;--tab-width:4;--bg:#fbfcfe;--surface:#f3f5f8;--text:#20242b;--muted:#68717e;--border:#d8dde5;--accent:#3168d5;--code-bg:#eef1f5;--code-text:#222833;--mark:#ffdf64;--mark-current:#ff9f43;--alert:#4b78d1}
    *{box-sizing:border-box}
    html{background:var(--bg);font-size:var(--font-size);scroll-behavior:smooth}
    body{margin:0;background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;line-height:var(--line-height);overflow-wrap:anywhere}
    body.font-serif{font-family:ui-serif,Georgia,"Times New Roman",serif}body.font-monospaced{font-family:ui-monospace,"SFMono-Regular",Menlo,monospace}
    body.theme-dark{--bg:#15171b;--surface:#202329;--text:#e7eaf0;--muted:#a4abb7;--border:#393f49;--accent:#83a9ff;--code-bg:#1c1f25;--code-text:#e5e9f0;--mark:#705c13;--mark-current:#9b4c16}
    body.theme-paper{--bg:#f7f0df;--surface:#eee4cf;--text:#322d25;--muted:#716858;--border:#d4c6a8;--accent:#765b29;--code-bg:#e9dec8;--code-text:#352f27}
    @media(prefers-color-scheme:dark){body.theme-system{--bg:#15171b;--surface:#202329;--text:#e7eaf0;--muted:#a4abb7;--border:#393f49;--accent:#83a9ff;--code-bg:#1c1f25;--code-text:#e5e9f0;--mark:#705c13;--mark-current:#9b4c16}}
    @media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
    @media(prefers-reduced-transparency:reduce){#markdown-preview-toc{background:var(--bg);backdrop-filter:none}}
    #markdown-preview-shell{zoom:var(--preview-zoom);display:grid;grid-template-columns:minmax(0,1fr);min-height:100vh}
    #markdown-preview-content,#markdown-preview-source{width:min(calc(100% - 48px),var(--content-width));margin:0 auto;padding:42px 0 72px}
    #markdown-preview-content[hidden],#markdown-preview-source[hidden]{display:none!important}
    body[data-view=source] #markdown-preview-toc{display:none!important}
    #markdown-preview-toc{position:fixed;z-index:2;top:24px;left:20px;width:220px;max-height:calc(100vh - 48px);overflow:auto;padding:14px;border:1px solid var(--border);border-radius:12px;background:color-mix(in srgb,var(--bg) 92%,transparent);backdrop-filter:blur(16px);font-size:.84rem}
    #markdown-preview-toc+.markdown-preview-content{margin-left:260px}.toc-title{font-weight:700;margin:0 0 8px}.toc-title+ol{list-style:none;padding:0;margin:0}.toc-title+ol li{margin:3px 0}.toc-title+ol a{display:block;color:var(--muted);text-decoration:none;border-radius:5px;padding:2px 5px}.toc-title+ol a:hover{color:var(--accent);background:var(--surface)}.toc-level-2{padding-left:10px}.toc-level-3{padding-left:20px}.toc-level-4,.toc-level-5,.toc-level-6{padding-left:30px}
    @media(min-width:1180px){#markdown-preview-toc~#markdown-preview-content{transform:translateX(120px)}}
    @media(max-width:900px){#markdown-preview-toc{position:relative;top:auto;left:auto;width:min(calc(100% - 48px),var(--content-width));max-height:none;margin:24px auto 0}#markdown-preview-toc~#markdown-preview-content{transform:none}}
    h1,h2,h3,h4,h5,h6{line-height:1.25;margin:1.55em 0 .65em;scroll-margin-top:22px;letter-spacing:-.015em}h1{font-size:2em;border-bottom:1px solid var(--border);padding-bottom:.3em}h2{font-size:1.55em;border-bottom:1px solid var(--border);padding-bottom:.25em}h3{font-size:1.28em}h4{font-size:1.1em}.heading-anchor{float:left;width:1.05em;margin-left:-1.1em;color:transparent;text-decoration:none;font-weight:400}.heading-anchor:focus,.heading-anchor:hover,h1:hover>.heading-anchor,h2:hover>.heading-anchor,h3:hover>.heading-anchor,h4:hover>.heading-anchor,h5:hover>.heading-anchor,h6:hover>.heading-anchor{color:var(--accent)}
    p{margin:.85em 0}a{color:var(--accent);text-underline-offset:2px}.blocked-link{color:var(--muted);text-decoration:line-through;text-decoration-thickness:1px}strong{font-weight:700}del{color:var(--muted)}mark:not(.search-match){background:color-mix(in srgb,var(--mark) 72%,transparent);color:inherit;border-radius:3px;padding:0 .12em}sub,sup{line-height:0}.footnote-ref{font-size:.72em}.footnotes{margin-top:2.6em;color:var(--muted);font-size:.9em}.footnotes ol{padding-left:1.4em}.footnotes li{margin:.4em 0}.footnote-number{font-variant-numeric:tabular-nums}.footnote-backlink{text-decoration:none;margin-left:.25em}hr{height:1px;border:0;background:var(--border);margin:2em 0}
    img{display:block;max-width:100%;height:auto;margin:1.2em auto;border-radius:8px}.image-placeholder{display:inline-block;padding:.15em .5em;border:1px dashed var(--border);border-radius:5px;color:var(--muted)}
    blockquote{margin:1.15em 0;padding:.1em 1em;border-left:4px solid var(--border);color:var(--muted)}.quote-details{margin:1.15em 0;padding:.65em 1em;border-left:4px solid var(--border);background:var(--surface);border-radius:0 8px 8px 0}.quote-details summary{cursor:pointer;font-weight:600}.quote-details blockquote{margin:.65em 0 0}
    ul,ol{padding-left:1.6em}.task-list{list-style:none;padding-left:.2em}.task-item{display:flex;gap:.55em;align-items:flex-start}.task-item input{margin-top:.42em;accent-color:var(--accent)}
    .table-scroll{overflow-x:auto;margin:1.2em 0}table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums}th,td{padding:.55em .7em;border:1px solid var(--border)}thead th{background:var(--surface);font-weight:650}.front-matter{margin:0 0 1.6em;border:1px solid var(--border);border-radius:10px;padding:.65em .85em}.front-matter summary{cursor:pointer;color:var(--muted);font-weight:650}.front-matter table{margin-top:.65em}.front-matter th{width:28%;text-align:left}.align-center{text-align:center}.align-right{text-align:right}.align-left{text-align:left}
    code,pre{font-family:ui-monospace,"SFMono-Regular",Menlo,Consolas,monospace}.inline-code{font-size:.88em;background:var(--code-bg);color:var(--code-text);border:1px solid var(--border);border-radius:5px;padding:.12em .35em}.code-container{position:relative;margin:1.2em 0}.code-language{position:absolute;right:10px;top:7px;color:var(--muted);font:600 .7rem -apple-system,BlinkMacSystemFont,sans-serif;text-transform:uppercase;letter-spacing:.04em}.code-block{margin:0;padding:1em;overflow:auto;tab-size:var(--tab-width);border:1px solid var(--border);border-radius:9px;background:var(--code-bg);color:var(--code-text);font-size:.86em;line-height:1.55}.code-line,.source-line{display:grid;grid-template-columns:3.4em minmax(0,1fr)}.line-number{color:var(--muted);text-align:right;padding-right:1.1em;user-select:none}.line-content{white-space:pre-wrap}
    .syntax-keyword{color:#9b4dca;font-weight:600}.syntax-string{color:#287a42}.syntax-number{color:#b14f28}.syntax-comment{color:var(--muted);font-style:italic}body.theme-dark .syntax-keyword,body.code-theme-monokai .syntax-keyword,body.code-theme-atomOneDark .syntax-keyword{color:#c792ea}body.theme-dark .syntax-string,body.code-theme-monokai .syntax-string,body.code-theme-atomOneDark .syntax-string{color:#a5d66a}body.theme-dark .syntax-number,body.code-theme-monokai .syntax-number,body.code-theme-atomOneDark .syntax-number{color:#f29d65}
    body.code-theme-github{--code-bg:#f6f8fa;--code-text:#24292f}body.theme-dark.code-theme-github{--code-bg:#0d1117;--code-text:#e6edf3}body.code-theme-monokai{--code-bg:#272822;--code-text:#f8f8f2}body.code-theme-atomOneDark{--code-bg:#282c34;--code-text:#abb2bf}body.code-theme-graphite{--code-bg:#272b33;--code-text:#e7e9ed}body.code-theme-ocean{--code-bg:#102a36;--code-text:#d5edf5}body.code-theme-dusk{--code-bg:#2c2233;--code-text:#f0ddec}body.code-theme-paper{--code-bg:#eee6d5;--code-text:#342e25}
    .alert{--alert:#4b78d1;margin:1.15em 0;padding:.8em 1em;border-left:5px solid var(--alert);background:color-mix(in srgb,var(--alert) 10%,var(--bg));border-radius:0 9px 9px 0}.alert-title{color:var(--alert);font-weight:750;margin-bottom:.25em}.alert-tip{--alert:#26865c}.alert-important{--alert:#7658b5}.alert-warning{--alert:#b16a10}.alert-caution{--alert:#c54747}
    .math{font-family:"New York",Cambria,Georgia,serif;background:var(--surface);border-radius:7px;color:var(--text)}.math-inline{padding:.08em .3em;white-space:nowrap}.math-display{margin:1.2em 0;padding:1em;text-align:center;white-space:pre-wrap;overflow:auto}.typst-fallback{margin:1.2em 0;padding:1em}.typst-fallback figcaption,.diagram-fallback figcaption{color:var(--muted);font-size:.85em;margin-bottom:.65em}
    .diagram{margin:1.35em 0;padding:1em;border:1px solid var(--border);border-radius:10px;background:var(--surface);overflow:auto}.diagram svg{display:block;width:100%;min-width:420px;max-height:660px}.diagram-node{fill:var(--bg);stroke:var(--accent);stroke-width:2}.diagram-label,.chart-label{fill:var(--text);font:14px -apple-system,BlinkMacSystemFont,sans-serif}.diagram-edge{stroke:var(--muted);stroke-width:2}.diagram-arrow{fill:var(--muted)}.chart-axis{stroke:var(--muted);stroke-width:1}.chart-bar{fill:var(--accent)}.chart-label{font-size:11px}
    #markdown-preview-source{border:0;background:var(--bg);color:var(--text);font:1em/var(--line-height) ui-monospace,"SFMono-Regular",Menlo,monospace;white-space:pre-wrap;tab-size:var(--tab-width);outline:none}.search-match{background:var(--mark);color:inherit;border-radius:2px}.search-current{background:var(--mark-current);outline:2px solid color-mix(in srgb,var(--mark-current) 55%,transparent)}
    @media print{:root{color-scheme:light;--bg:#fff;--surface:#f5f5f5;--text:#111;--muted:#555;--border:#ccc;--accent:#174ea6}#markdown-preview-shell{zoom:1}#markdown-preview-toc{display:none!important}#markdown-preview-content,#markdown-preview-source{width:100%;padding:0}.heading-anchor{display:none}a{color:inherit;text-decoration:underline}.code-block,.diagram,.front-matter{break-inside:avoid}body{-webkit-print-color-adjust:exact;print-color-adjust:exact}}
    """#

    private static let hooksScript = #"""
    (()=>{"use strict";
      const content=document.getElementById("markdown-preview-content");
      const source=document.getElementById("markdown-preview-source");
      const clamp=(value,min,max)=>Math.min(max,Math.max(min,value));
      const scrollBehavior=()=>window.matchMedia?.("(prefers-reduced-motion: reduce)").matches?"auto":"smooth";
      let scrollReportScheduled=false;
      function reportScrollPosition(){
        if(scrollReportScheduled)return;scrollReportScheduled=true;
        requestAnimationFrame(()=>{scrollReportScheduled=false;window.webkit?.messageHandlers?.commandlyMarkdownScroll?.postMessage(Number.isFinite(window.scrollY)?window.scrollY:0)});
      }
      let searchState={signature:"",index:-1};
      function clearSearch(reset=true){
        document.querySelectorAll("mark.search-match").forEach(mark=>mark.replaceWith(document.createTextNode(mark.textContent||"")));
        content.normalize();source.normalize();
        if(reset)searchState={signature:"",index:-1};
        return true;
      }
      function setSourceVisible(visible){
        const show=Boolean(visible);clearSearch();content.hidden=show;source.hidden=!show;document.body.dataset.view=show?"source":"rendered";return show;
      }
      function scrollToAnchor(value){
        if(typeof value!=="string"||value.length>256)return false;
        let anchor=value.startsWith("#")?value.slice(1):value;
        try{anchor=decodeURIComponent(anchor)}catch(_error){return false}
        if(!/^[\p{L}\p{N}_-]+$/u.test(anchor))return false;
        const target=document.getElementById(anchor);if(!target)return false;target.scrollIntoView({block:"start",behavior:scrollBehavior()});return true;
      }
      function setZoom(value){
        const number=Number(value);if(!Number.isFinite(number))return null;
        const zoom=clamp(number,.5,3);document.documentElement.style.setProperty("--preview-zoom",String(zoom));return zoom;
      }
      function safePattern(query,options){
        if(query.length>256)return{error:"Search query is too long."};
        let pattern=query;
        if(options.regex){
          // JavaScript regular expressions have no cancellation or execution timeout. Keep the
          // user-facing mode useful for anchors, alternation, dots, and character classes while
          // rejecting every repetition construct, backreference, and lookaround that can cause
          // pathological backtracking over a large local document.
          if(query.length>128||/(^|[^\\])[+*?{]/.test(query)||/\\[1-9]|\(\?[=!<:]/.test(query))return{error:"This regular expression uses an unsupported repetition or lookaround."};
        }else{pattern=query.replace(/[.*+?^${}()|[\]\\]/g,"\\$&")}
        if(options.wholeWord)pattern="\\b(?:"+pattern+")\\b";
        try{return{expression:new RegExp(pattern,options.caseSensitive?"gu":"giu")}}catch(error){return{error:String(error.message||error)}}
      }
      function search(query,rawOptions={}){
        if(typeof query!=="string"||query.length===0){clearSearch();return{current:0,total:0,error:null}}
        const options={caseSensitive:Boolean(rawOptions.caseSensitive),wholeWord:Boolean(rawOptions.wholeWord),regex:Boolean(rawOptions.regex),backwards:Boolean(rawOptions.backwards)};
        const signature=JSON.stringify([query,options.caseSensitive,options.wholeWord,options.regex]);
        const prior=searchState.signature===signature?searchState.index:-1;
        clearSearch(false);
        const compiled=safePattern(query,options);if(compiled.error){searchState={signature:"",index:-1};return{current:0,total:0,error:compiled.error}}
        const root=source.hidden?content:source;
        const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT,{acceptNode(node){const parent=node.parentElement;if(!parent||parent.closest("script,style,mark,[hidden]"))return NodeFilter.FILTER_REJECT;return node.nodeValue?NodeFilter.FILTER_ACCEPT:NodeFilter.FILTER_REJECT}});
        const nodes=[];while(walker.nextNode())nodes.push(walker.currentNode);
        const marks=[];
        for(const node of nodes){
          const text=node.nodeValue||"";compiled.expression.lastIndex=0;const matches=[];let match;
          while((match=compiled.expression.exec(text))!==null&&marks.length+matches.length<2000){if(match[0].length===0){compiled.expression.lastIndex++;continue}matches.push({start:match.index,end:match.index+match[0].length})}
          if(matches.length===0)continue;
          const fragment=document.createDocumentFragment();let offset=0;
          for(const found of matches){fragment.append(document.createTextNode(text.slice(offset,found.start)));const mark=document.createElement("mark");mark.className="search-match";mark.textContent=text.slice(found.start,found.end);fragment.append(mark);marks.push(mark);offset=found.end}
          fragment.append(document.createTextNode(text.slice(offset)));node.replaceWith(fragment);
          if(marks.length>=2000)break;
        }
        if(marks.length===0){searchState={signature,index:-1};return{current:0,total:0,error:null}}
        let index;if(prior<0)index=options.backwards?marks.length-1:0;else index=(prior+(options.backwards?-1:1)+marks.length)%marks.length;
        marks[index].classList.add("search-current");marks[index].scrollIntoView({block:"center",behavior:scrollBehavior()});searchState={signature,index};
        return{current:index+1,total:marks.length,error:null};
      }
      document.addEventListener("click",event=>{const link=event.target.closest?.("a[href^='#']");if(link){event.preventDefault();scrollToAnchor(link.getAttribute("href")||"")}});
      window.addEventListener("scroll",reportScrollPosition,{passive:true});reportScrollPosition();
      Object.defineProperty(window,"commandlyMarkdown",{value:Object.freeze({setSourceVisible,scrollToAnchor,setZoom,search,clearSearch}),writable:false,configurable:false});
    })();
    """#
}
