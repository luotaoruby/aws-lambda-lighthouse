const AWS = require("aws-sdk")
const ddb = new AWS.DynamoDB.DocumentClient()

AWS.config.update({ region: process.env.REGION })

const s3 = new AWS.S3()

const pageCountCompleted = (image)=> {
  parseInt(image.PageConutSuccess.N, 10) + parseInt(image.PageCountError.N, 10)
}

async function setDynamoTimestampNow(jobId, attr) {
  const now = new Date()

  const params = {
    TableName: process.env.JOBS_TABLE_NAME,
    Key: {
      JobId: jobId
    },
    UpdateExpression: `SET ${attr} = :val`,
    ExpressionAtrributeValues: {
      ":val": now.toISOString()
    },
    ReturnValues: "UPDATED_NEW"
  }

  return ddb.update(params).promise()
}

exports.handler = async function(event, context) {
  const record = event.Records[0]
  if (record.eventName !== "MODIFY") {
    return Promise.resolve()
  }

  const oldPageCountCompleted = pageCountCompleted(record.dynamodb.OldImage)
  const newPageCountCompleted = pageCountCompleted(record.dynamodb.NewImage)
  const totalPageCount = parseInt(
    record.dynamodb.NewImage.PageCountTotal.N,
    10
  )

  const jobJustFinished = (
    oldPageCountCompleted !== newPageCountCompleted &&
      newPageCountCompleted >= totalPageCount
  )

  if (!jobJustFinished) {
    return Promise.resolve()
  }

  await setDynamoTimestampNow(
    record.dynamodb.NewImage.JobId.S,
    "LighthouseRunEndTime"
  )

  return Promise.resolve()
}
