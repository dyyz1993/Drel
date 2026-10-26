import datetime, json, pathlib, re, sys, os
out=sys.argv[1]; stamp=sys.argv[2]
g=pathlib.Path(sys.argv[3]); b=pathlib.Path(sys.argv[4])
def parse(path):
    try: data=json.loads(path.read_text())
    except Exception: return {}
    text=data.get("text","")
    if data.get("captcha"): state="needs_human"
    elif "did not match any documents" in text or "未找到相关结果" in text: state="not_indexed"
    else:
        m=re.search(r'(?:About|找到约)\s*([\d,\.]+)\s*(?:results|条结果)', text)
        n=int(re.sub(r"[^\d]","",m.group(1)) or 0) if m else 0
        state="indexed" if n>0 or ("drel.app" in text and "Web results" in text) else "unknown"
    return {"state":state,"url":data.get("url"),"title":data.get("title"),"captcha":bool(data.get("captcha")),"text_chars":len(text)}
report={"schema":"drel.search_index.v1","checked_at_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"domain":"drel.app","google":parse(g),"baidu":parse(b),"evidence":{"google_raw":str(g.relative_to(pathlib.Path.cwd())),"baidu_raw":str(b.relative_to(pathlib.Path.cwd()))},"automation_policy":"CAPTCHA stops monitoring and requires human intervention."}
outp=pathlib.Path(out); outp.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n"); outp.with_name("latest.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
