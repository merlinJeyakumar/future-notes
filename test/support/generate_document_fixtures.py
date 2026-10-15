"""Generate tiny synthetic preview fixtures; Python standard library only.

Legacy DOC structure follows the MIT-licensed Office Oxide synthetic writer:
https://github.com/yfedoseev/office_oxide/blob/v0.1.15/tests/common/mod.rs
Copyright (c) 2026 Yury Fedoseev. License: ../../licenses/office-oxide-MIT.txt.
No personal documents, macros, external links or embedded objects.
"""
from pathlib import Path
import struct as s
import zipfile

ROOT = Path(__file__).resolve().parents[1] / 'fixtures' / 'documents'
ROOT.mkdir(parents=True, exist_ok=True)

def u16(b, o, v): s.pack_into('<H', b, o, v)
def u32(b, o, v): s.pack_into('<I', b, o, v)

def cfb(streams):
    # Regular streams padded to the 4096-byte mini-stream cutoff.
    sizes = [max(4096, (len(data)+511)//512*512) for _, data in streams]
    b = bytearray(1536 + sum(sizes))
    b[:8] = bytes.fromhex('d0cf11e0a1b11ae1')
    for o,v in [(0x18,0x3e),(0x1a,3),(0x1c,0xfffe),(0x1e,9),(0x20,6)]: u16(b,o,v)
    for o,v in [(0x2c,1),(0x30,0),(0x38,4096),(0x3c,0xfffffffe),(0x44,0xfffffffe),(0x4c,1)]: u32(b,o,v)
    for i in range(1,109): u32(b,0x4c+4*i,0xffffffff)
    for i in range(128): u32(b,1024+4*i,0xffffffff)
    u32(b,1024,0xfffffffe); u32(b,1028,0xfffffffd)
    def entry(index,name,kind,start,length,child=0xffffffff,right=0xffffffff):
        o=512+index*128
        encoded=name.encode('utf-16le'); b[o:o+len(encoded)]=encoded
        u16(b,o+0x40,len(encoded)+2); b[o+0x42]=kind; b[o+0x43]=1
        for k,v in [(0x44,0xffffffff),(0x48,right),(0x4c,child),(0x74,start),(0x78,length)]: u32(b,o+k,v)
    entry(0,'Root Entry',5,0xfffffffe,0,child=1)
    sector=2
    for i,((name,data),size) in enumerate(zip(streams,sizes),1):
        entry(i,name,2,sector,size,right=i+1 if i<len(streams) else 0xffffffff)
        b[512+sector*512:512+sector*512+len(data)]=data
        n=size//512
        for k in range(sector,sector+n): u32(b,1024+4*k,k+1 if k<sector+n-1 else 0xfffffffe)
        sector+=n
    return b

text='Synthetic legacy document preview.\r'
wd=bytearray(2048)
u16(wd,0,0xa5ec); u16(wd,2,0xc1); u32(wd,0x4c,len(text))
u32(wd,0x1a6,21); u32(wd,0x102,21); u32(wd,0x106,12)
u32(wd,1024,1536); u32(wd,1028,1536+len(text)*2)
wd[1032]=11; wd[1046:1050]=bytes([0,1,0,0]); wd[1535]=1
wd[1536:1536+len(text)*2]=text.encode('utf-16le')
table=b'\x02'+s.pack('<IIIHIH',16,0,len(text),0,1536,0)+s.pack('<III',0,len(text),2)
(ROOT/'sample.doc').write_bytes(cfb([('WordDocument',wd),('0Table',table)]))

def rec(kind,data=b''): return s.pack('<HH',kind,len(data))+data
def bof(kind): return rec(0x809,s.pack('<HHHHII',0x600,kind,0xdbb,1997,0x41,6))
label=b'Synthetic spreadsheet'
sst=rec(0xfc,s.pack('<IIHB',1,1,len(label),0)+label)
name=b'Overview'
bound=lambda offset: rec(0x85,s.pack('<IBBBB',offset,0,0,len(name),0)+name)
globals_=bof(5)+sst+bound(0)+rec(0xa)
globals_=bof(5)+sst+bound(len(globals_))+rec(0xa)
sheet=bof(0x10)+rec(0x200,s.pack('<IIHHH',0,2,0,2,0))+rec(0xfd,s.pack('<HHHI',0,0,0,0))+rec(0x203,s.pack('<HHHd',1,1,0,42.0))+rec(0xa)
(ROOT/'sample.xls').write_bytes(cfb([('Workbook',globals_+sheet)]))

def zip_parts(name,parts):
    with zipfile.ZipFile(ROOT/name,'w',zipfile.ZIP_DEFLATED) as z:
        for path,xml in parts.items():
            info=zipfile.ZipInfo(path,(2026,1,1,0,0,0)); info.compress_type=zipfile.ZIP_DEFLATED
            z.writestr(info,xml)

zip_parts('sample.docx',{
 '[Content_Types].xml':'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
 '_rels/.rels':'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
 'word/document.xml':'<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Synthetic document preview</w:t></w:r></w:p><w:tbl><w:tr><w:tc><w:p><w:r><w:t>Table cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body></w:document>',
})
zip_parts('sample.xlsx',{
 '[Content_Types].xml':'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/></Types>',
 '_rels/.rels':'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
 'xl/workbook.xml':'<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Overview" sheetId="1" r:id="rId1"/></sheets></workbook>',
 'xl/_rels/workbook.xml.rels':'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
 'xl/worksheets/sheet1.xml':'<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Synthetic spreadsheet</t></is></c></row><row r="2"><c r="B2"><v>42</v></c></row></sheetData></worksheet>',
})

objects=[b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 >>',
 b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
 b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',None,
 b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 7 0 R >>',None]
for i,txt in [(4,b'Synthetic PDF preview'),(6,b'Second page')]:
    content=b'BT /F1 20 Tf 50 700 Td ('+txt+b') Tj ET'
    objects[i]=b'<< /Length '+str(len(content)).encode()+b' >>\nstream\n'+content+b'\nendstream'
pdf=bytearray(b'%PDF-1.4\n'); offsets=[0]
for i,obj in enumerate(objects,1):
    offsets.append(len(pdf)); pdf+=str(i).encode()+b' 0 obj\n'+obj+b'\nendobj\n'
start=len(pdf); pdf+=b'xref\n0 8\n0000000000 65535 f \n'
for off in offsets[1:]: pdf+=f'{off:010d} 00000 n \n'.encode()
pdf+=b'trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n'+str(start).encode()+b'\n%%EOF\n'
(ROOT/'sample.pdf').write_bytes(pdf)
print('Generated five synthetic documents in',ROOT)
