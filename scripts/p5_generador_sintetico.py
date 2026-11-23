#!/usr/bin/env python3
"""Genera CSV sintético para pruebas sin escribir datos operativos."""
import csv,random,datetime,argparse
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--cantidad',type=int,default=5000);p.add_argument('--salida',default='p5_incidentes_sinteticos.csv');a=p.parse_args()
random.seed(42)
with Path(a.salida).open('w',newline='',encoding='utf-8') as out:
 w=csv.writer(out);w.writerow(['id_sintetico','servicio','municipio_codigo','inicio_en','restablecido_en','estado'])
 for i in range(a.cantidad):
  t=datetime.datetime(2026,1,1,tzinfo=datetime.timezone.utc)+datetime.timedelta(minutes=random.randint(0,450000))
  duration=datetime.timedelta(minutes=random.randint(10,360))
  w.writerow([i+1,random.choice(['energia','gas','acueducto','aseo','alcantarillado']),random.choice(['11001','05001','76001','08001']),t.isoformat(),(t+duration).isoformat(),'restablecido'])
print(f'CSV creado: {a.salida} ({a.cantidad} filas)')
