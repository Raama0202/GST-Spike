@echo off
cd /d "C:\GST software"
node apps\api\dev-memory-api.cjs > api-memory.log 2> api-memory.err.log
