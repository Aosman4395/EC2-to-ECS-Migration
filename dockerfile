FROM python:3.9-slim 

WORKDIR /legacy-app

COPY legacy-app/app /legacy-app

RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 5000

RUN useradd -m legacyuser
USER legacyuser

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "wsgi:app"]