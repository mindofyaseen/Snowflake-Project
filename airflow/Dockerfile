FROM apache/airflow:2.11.0-python3.12

COPY airflow/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

COPY src /opt/carematch/src

