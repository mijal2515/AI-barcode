from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import pymysql
import pandas as pd
import io

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"], 
    allow_headers=["*"],
)

DB_CONFIG = {
    'host': '127.0.0.1',
    'user': 'root',
    'password': 'wodnjs2515',
    'db': 'instrument_db',
    'charset': 'utf8mb4',
    'cursorclass': pymysql.cursors.DictCursor
}

class InstrumentModel(BaseModel):
    barcode: str
    name: str
    status: str = "보관중"
    school: str = ""

class HistoryModel(BaseModel):
    time: str
    type: str
    content: str

# id 리스트를 받기 위한 요청 모델
class DeleteHistoryByIdRequest(BaseModel):
    ids: List[int]

# ==========================================
# 🎸 1. 악기(Instruments) 관련 API
# ==========================================

@app.post("/instruments")
def create_instrument(instrument: InstrumentModel):
    try:
        conn = pymysql.connect(**DB_CONFIG)
        with conn.cursor() as cursor:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS instruments (
                    barcode VARCHAR(100) PRIMARY KEY,
                    name VARCHAR(100),
                    status VARCHAR(50),
                    school VARCHAR(100)
                )
            """)
            sql = """
                REPLACE INTO instruments (barcode, name, status, school)
                VALUES (%s, %s, %s, %s)
            """
            cursor.execute(sql, (instrument.barcode, instrument.name, instrument.status, instrument.school))
        conn.commit()
        return {"status": "success", "message": "악기가 성공적으로 등록되었습니다."}
    except Exception as e:
        return {"status": "error", "message": f"악기 등록 실패: {str(e)}"}
    finally:
        if 'conn' in locals() and conn.open:
            conn.close()

@app.get("/instruments")
def get_instruments():
    try:
        conn = pymysql.connect(**DB_CONFIG)
        with conn.cursor() as cursor:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS instruments (
                    barcode VARCHAR(100) PRIMARY KEY,
                    name VARCHAR(100),
                    status VARCHAR(50),
                    school VARCHAR(100)
                )
            """)
            cursor.execute("SELECT barcode, name, status, school FROM instruments")
            data = cursor.fetchall()
            return {"status": "success", "data": data}
    except Exception as e:
        return {"status": "error", "message": str(e)}
    finally:
        if 'conn' in locals() and conn.open:
            conn.close()

@app.post("/upload-excel")
async def upload_excel(file: UploadFile = File(...)):
    try:
        contents = await file.read()
        df = pd.read_excel(io.BytesIO(contents))
        df.columns = df.columns.str.strip().str.lower()
        
        barcode_col = '바코드' if '바코드' in df.columns else 'barcode'
        name_col = '악기명' if '악기명' in df.columns else 'name'
        
        if barcode_col not in df.columns or name_col not in df.columns:
            raise HTTPException(status_code=400, detail="엑셀 열 이름이 맞지 않습니다!")

        conn = pymysql.connect(**DB_CONFIG)
        inserted_count = 0
        try:
            with conn.cursor() as cursor:
                cursor.execute("""
                    CREATE TABLE IF NOT EXISTS instruments (
                        barcode VARCHAR(100) PRIMARY KEY,
                        name VARCHAR(100),
                        status VARCHAR(50),
                        school VARCHAR(100)
                    )
                """)
                for index, row in df.iterrows():
                    sql = """
                        REPLACE INTO instruments (barcode, name, status, school) 
                        VALUES (%s, %s, %s, %s)
                    """
                    cursor.execute(sql, (str(row[barcode_col]), str(row[name_col]), "보관중", ""))
                    inserted_count += 1
            conn.commit()
            return {"status": "success", "message": f"총 {inserted_count}개의 악기가 등록되었습니다."}
        except Exception as db_err:
            raise HTTPException(status_code=500, detail=f"DB 저장 실패: {str(db_err)}")
        finally:
            conn.close()
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/instruments/{barcode}")
def delete_instrument(barcode: str):
    try:
        conn = pymysql.connect(**DB_CONFIG)
        with conn.cursor() as cursor:
            sql = "DELETE FROM instruments WHERE barcode = %s"
            cursor.execute(sql, (barcode,))
            if cursor.rowcount == 0:
                return {"status": "error", "message": "해당 바코드의 악기를 찾을 수 없습니다."}
        conn.commit()
        return {"status": "success", "message": "성공적으로 삭제되었습니다."}
    except Exception as e:
        return {"status": "error", "message": f"서버 오류: {str(e)}"}
    finally:
        if 'conn' in locals() and conn.open:
            conn.close()


# ==========================================
# 📜 2. 기록(History) 관련 API
# ==========================================

@app.post("/history")
def create_history(log: HistoryModel):
    try:
        conn = pymysql.connect(**DB_CONFIG)
        with conn.cursor() as cursor:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS history (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    time VARCHAR(100),
                    type VARCHAR(50),
                    content TEXT
                )
            """)
            sql = "INSERT INTO history (time, type, content) VALUES (%s, %s, %s)"
            cursor.execute(sql, (log.time, log.type, log.content))
        conn.commit()
        return {"status": "success", "message": "기록이 DB에 저장되었습니다."}
    except Exception as e:
        return {"status": "error", "message": str(e)}
    finally:
        if 'conn' in locals() and conn.open:
            conn.close()

@app.get("/history")
def get_history():
    try:
        conn = pymysql.connect(**DB_CONFIG)
        with conn.cursor() as cursor:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS history (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    time VARCHAR(100),
                    type VARCHAR(50),
                    content TEXT
                )
            """)
            # 🔥 핵심 수정: 조회할 때 id 컬럼도 받아옵니다.
            sql = "SELECT id, time, type, content FROM history ORDER BY id DESC"
            cursor.execute(sql)
            data = cursor.fetchall()
        return {"status": "success", "data": data}
    except Exception as e:
        return {"status": "error", "message": str(e)}
    finally:
        if 'conn' in locals() and conn.open:
            conn.close()

@app.post("/history/delete-multiple")
def delete_multiple_history(request: DeleteHistoryByIdRequest):
    try:
        # 🔥 핵심 수정: 하드코딩된 비밀번호 대신 상단의 올바른 DB_CONFIG를 사용합니다.
        conn = pymysql.connect(**DB_CONFIG)
        with conn.cursor() as cursor:
            delete_data = [(record_id,) for record_id in request.ids]
            # 🔥 핵심 수정: 고유 번호(id) 기준으로 삭제 쿼리 실행
            cursor.executemany("DELETE FROM history WHERE id = %s", delete_data)
            affected_rows = cursor.rowcount 
        conn.commit()

        # 실제로 지워진 데이터가 없다면 예외를 발생시켜 플러터가 감지하도록 유도
        if affected_rows == 0:
            raise HTTPException(status_code=400, detail="삭제할 데이터를 DB에서 찾지 못했습니다.")

        return {"status": "success", "message": f"{affected_rows}건의 기록이 삭제되었습니다."}
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if 'conn' in locals() and conn.open:
            conn.close()