##### MLflow Tracking
```
- install dependencies
pip install mlflow

- activate user interface
mlflow ui

- navigate to this location to acccess ui board (or click link in terminal)
http://localhost:5000/
```

##### Projects
```
- running locally
mlflow run .
```

##### Model Registry & Lifecycle Management
```
- running ml server for model lifecycle management, allows ml model registering
mlflow server --backend-store-uri sqlite:///mlruns.db --default-artifact-root ./mlruns

- transition from stored -> staging -> production -> archieve, click on models/versions then see the drop-down menu

- ml lifecycle workflow logic can be managed using conditional statements based on accuracy filters (TDD) to declare the version and stage of model for deployment (automated ml-ops)
- tf-serving can be done by using mlflow to retrieve the best existing model and copying the model into tf-serving model directory
```

##### Model Deployment & Serving
```
- models can be served using the below based on the run_id we want
mlflow models serve --model-uri ./mlruns/<job_id>/data/model

- the deployed model can then be invoked through a REST API query
curl -d '{"data":<insert data here>}' -H 'Content-Type: application/json'  localhost:5000/invocations
```
