from flask import Flask, render_template

app = Flask(__name__)

# 메인 페이지 (AI 갤러리)
@app.route('/')
def home():
    return render_template('index.html')

# 공지사항 페이지
@app.route('/notices')
def notices():
    return render_template('notice.html')

# 이용약관 전문
@app.route('/terms')
def terms():
    return render_template('terms.html')

# 개인정보처리방침 전문 (개인정보 보호법 제30조에 따라 상시 게재)
@app.route('/privacy')
def privacy():
    return render_template('privacy.html')

# 관리자 업로드 페이지 (코디 사진 업로드 + AI 분석)
@app.route('/admin')
def admin_upload():
    return render_template('admin_upload.html')

if __name__ == '__main__':
    app.run(debug=True)
