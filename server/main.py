import os
from fastapi import FastAPI, UploadFile, File, HTTPException
import openpyxl
from datetime import datetime
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import pymysql
import pandas as pd
import io
from urllib.parse import quote

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 클라우드타입 배포 시 대시보드의 "환경 변수"에서 아래 값들을 설정하세요.
# (로컬 개발 환경에서는 기존 기본값이 그대로 사용됩니다.)
DB_CONFIG = {
    'host': os.environ.get('DB_HOST', '127.0.0.1'),
    'port': int(os.environ.get('DB_PORT', 3306)),
    'user': os.environ.get('DB_USER', 'root'),
    'password': os.environ.get('DB_PASSWORD', 'wodnjs2515'),
    'db': os.environ.get('DB_NAME', 'instrument_db'),
    'charset': 'utf8mb4',
    'cursorclass': pymysql.cursors.DictCursor
}

def _ensure_history_columns(cursor):
    """구버전 history 테이블(content 컬럼만 존재)에 barcode/name/school 컬럼을 추가합니다."""
    for column_sql in (
        "ALTER TABLE history ADD COLUMN barcode VARCHAR(100)",
        "ALTER TABLE history ADD COLUMN name VARCHAR(100)",
        "ALTER TABLE history ADD COLUMN school VARCHAR(100)",
    ):
        try:
            cursor.execute(column_sql)
        except pymysql.err.OperationalError as e:
            if e.args[0] != 1060:  # 1060 = Duplicate column name (이미 존재하면 무시)
                raise

class InstrumentModel(BaseModel):
    barcode: str
    name: str
    status: str = "보관중"
    school: str = ""

class InstrumentUpdateModel(BaseModel):
    name: str
    status: str
    school: str = ""

class HistoryModel(BaseModel):
    time: str
    type: str
    barcode: str
    name: str
    school: str = ""

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

@app.put("/instruments/{barcode}")
def update_instrument(barcode: str, instrument: InstrumentUpdateModel):
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
            sql = "UPDATE instruments SET name = %s, status = %s, school = %s WHERE barcode = %s"
            cursor.execute(sql, (instrument.name, instrument.status, instrument.school, barcode))
            if cursor.rowcount == 0:
                # 🛠️ MySQL은 실제로 값이 바뀐 행이 없으면(내용이 이미 동일해도) rowcount를 0으로 주므로,
                # 존재 여부를 다시 확인해서 "찾을 수 없음" 오탐을 방지합니다.
                cursor.execute("SELECT 1 FROM instruments WHERE barcode = %s", (barcode,))
                if cursor.fetchone() is None:
                    return {"status": "error", "message": "해당 바코드의 악기를 찾을 수 없습니다."}
        conn.commit()
        return {"status": "success", "message": "악기 정보가 수정되었습니다."}
    except Exception as e:
        return {"status": "error", "message": f"악기 수정 실패: {str(e)}"}
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
                    barcode VARCHAR(100),
                    name VARCHAR(100),
                    school VARCHAR(100)
                )
            """)
            _ensure_history_columns(cursor)
            sql = "INSERT INTO history (time, type, barcode, name, school) VALUES (%s, %s, %s, %s, %s)"
            cursor.execute(sql, (log.time, log.type, log.barcode, log.name, log.school))
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
                    barcode VARCHAR(100),
                    name VARCHAR(100),
                    school VARCHAR(100)
                )
            """)
            _ensure_history_columns(cursor)
            # 🔥 핵심 수정: 조회할 때 id 컬럼도 받아옵니다.
            sql = "SELECT id, time, type, barcode, name, school FROM history ORDER BY id DESC"
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
@app.get("/history/export")
async def export_history():
    conn = None
    try:
        # 1. 데이터베이스 연결
        conn = pymysql.connect(**DB_CONFIG)
        
        # 2. 🛠️ 핵심 수정: 데이터베이스 내부의 datetime 컬럼을 'YYYY-MM-DD HH:mm' 형태의 문자열로 명확하게 포맷팅하여 조회
        # 만약 컬럼 타입이 VARCHAR인 경우에도 유연하게 대처할 수 있도록 처리합니다.
        query = "SELECT time, type, barcode, name, school FROM history ORDER BY id DESC"

        # 3. Pandas 데이터프레임으로 변환
        # 🛠️ DB_CONFIG의 DictCursor로 pd.read_sql을 그대로 쓰면 값 대신 컬럼명이 셀에 들어가는 pandas 버그가 있어,
        # 일반 튜플 커서로 직접 조회한 뒤 DataFrame을 만듭니다.
        with conn.cursor(pymysql.cursors.Cursor) as cursor:
            cursor.execute(query)
            rows = cursor.fetchall()
        df = pd.DataFrame(rows, columns=["시간", "구분", "바코드", "물품명", "대여처"])

        today_str = datetime.now().strftime("%Y-%m-%d")

        if not df.empty:
            # 5. 혹시라도 과거에 수동 입력하여 날짜 없이 시간만('16:32') 채워져 있는 데이터 보정 규칙
            def ensure_datetime_format(val):
                if pd.isnull(val):
                    return ""
                val_str = str(val).strip()
                
                # '16:32' 처럼 문자열 길이가 5자 이하이면서 콜론이 포함된 경우 오늘 날짜 강제 결합
                if len(val_str) <= 5 and ":" in val_str:
                    return f"{today_str} {val_str}"
                
                # '2026-07-09 16:32:00' 처럼 뒤에 초 단위가 붙어 나와 가독성이 떨어지는 경우 분 단위까지만 커트
                # 🛠️ 'YYYY-MM-DD HH:MM'(길이 16, 초 없음)까지 여기서 걸리면 val_str[16]에서 인덱스 범위 초과가 나므로
                # 초까지 포함된 길이(19)를 기준으로 판단합니다.
                if len(val_str) >= 19 and val_str[10] == ' ' and val_str[13] == ':' and val_str[16] == ':':
                    return val_str[:16]
                    
                return val_str
            
            # 시간 컬럼 전처리 적용
            df["시간"] = df["시간"].apply(ensure_datetime_format)
        
        # 6. 메모리 버퍼(BytesIO)에 openpyxl 엔진을 사용하여 엑셀 파일 빌드
        output = io.BytesIO()
        with pd.ExcelWriter(output, engine='openpyxl') as writer:
            df.to_excel(writer, index=False, sheet_name="Sheet1")
            
            # 엑셀 열 너비 자동 최적화 스타일링 코드 (선택 사항)
            worksheet = writer.sheets["Sheet1"]
            for col in worksheet.columns:
                max_len = max(len(str(cell.value or '')) for cell in col)
                col_letter = col[0].column_letter
                worksheet.column_dimensions[col_letter].width = max(max_len + 3, 12)
                
        output.seek(0)
        
        # 7. 파일 다운로드 스트림 응답 반환
        # 🛠️ Content-Disposition 헤더는 latin-1만 허용되므로 한글 파일명은 RFC 5987 형식(filename*)으로 인코딩
        filename = "DB_악기_입출고_기록.xlsx"
        encoded_filename = quote(filename)
        return StreamingResponse(
            output,
            media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            headers={"Content-Disposition": f"attachment; filename*=UTF-8''{encoded_filename}"}
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"엑셀 파일 생성 중 서버 오류 발생: {str(e)}")
        
    finally:
        # 데이터베이스 커넥션 자원 반환 안전 장치
        if conn and conn.open:
            conn.close()


# 🔥 [신규 추가] 5. 엑셀 파일을 업로드하여 기록(History)에 대량 저장
# [main_2.py 수정안] 엑셀 파일을 업로드하여 기록(History)에 대량 저장
@app.post("/history/import")
async def import_history(file: UploadFile = File(...)):
    if not file.filename.endswith(('.xlsx', '.xls')):
        return {"status": "error", "message": "엑셀 파일(.xlsx, .xls)만 업로드할 수 있습니다."}
    
    try:
        contents = await file.read()
        df = pd.read_excel(io.BytesIO(contents))
        
        required_columns = ["시간", "구분", "바코드", "물품명", "대여처"]
        if not all(col in df.columns for col in required_columns):
            return {"status": "error", "message": "엑셀 파일의 첫 줄(헤더)은 '시간', '구분', '바코드', '물품명', '대여처'여야 합니다."}

        conn = pymysql.connect(**DB_CONFIG)
        with conn.cursor() as cursor:
            _ensure_history_columns(cursor)

            sql = "INSERT INTO history (time, type, barcode, name, school) VALUES (%s, %s, %s, %s, %s)"

            # 🛠️ 이미 DB에 있는 (시간, 구분, 바코드, 물품명, 대여처) 조합을 미리 조회해 중복 업로드를 걸러냅니다.
            cursor.execute("SELECT time, type, barcode, name, school FROM history")
            existing_rows = {tuple('' if v is None else v for v in row.values()) for row in cursor.fetchall()}

            insert_data = []
            skipped = 0
            for index, row in df.iterrows():
                raw_time = row["시간"]
                type_val = str(row["구분"]).strip() if pd.notnull(row["구분"]) else ""
                barcode_val = str(row["바코드"]).strip() if pd.notnull(row["바코드"]) else ""
                name_val = str(row["물품명"]).strip() if pd.notnull(row["물품명"]) else ""
                school_val = str(row["대여처"]).strip() if pd.notnull(row["대여처"]) else ""

                # 🛠️ 날짜/시간 형식을 'YYYY-MM-DD HH:mm'으로 깔끔하게 표준화
                time_val = ""
                if pd.notnull(raw_time):
                    raw_time_str = str(raw_time).strip()
                    # 기존에 쓰던 단순 "17:15" 형태인 경우 그대로 유지
                    if len(raw_time_str) <= 5 and ":" in raw_time_str:
                        time_val = raw_time_str
                    else:
                        try:
                            # 엑셀 날짜 데이터 유형 및 다양한 표기법을 판별하여 포맷 변환 (초 단위 제외)
                            parsed_time = pd.to_datetime(raw_time)
                            time_val = parsed_time.strftime("%Y-%m-%d %H:%M")
                        except Exception:
                            time_val = raw_time_str

                if not time_val or not type_val:
                    continue

                record = (time_val, type_val, barcode_val, name_val, school_val)

                # DB에 이미 있거나, 같은 파일 안에서 이미 등록 대상으로 잡힌 완전히 동일한 행이면 건너뜁니다.
                if record in existing_rows:
                    skipped += 1
                    continue

                existing_rows.add(record)
                insert_data.append(record)

            if insert_data:
                cursor.executemany(sql, insert_data)
                conn.commit()
                affected = len(insert_data)
            else:
                affected = 0

        message = f"총 {affected}건의 기록 데이터가 성공적으로 업로드되었습니다."
        if skipped:
            message += f" (이미 동일한 기록 {skipped}건은 건너뛰었습니다.)"
        return {"status": "success", "message": message}
        
    except Exception as e:
        if 'conn' in locals() and conn.open:
            conn.rollback()
        return {"status": "error", "message": f"업로드 처리 중 에러 발생: {str(e)}"}
    finally:
        if 'conn' in locals() and conn.open:
            conn.close()


if __name__ == "__main__":
    import uvicorn
    # 클라우드타입은 실행할 포트를 PORT 환경 변수로 전달합니다.
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", 8000)))