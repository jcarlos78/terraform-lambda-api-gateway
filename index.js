exports.handler = (event) => {
    console.log('Hello, logs!');
    
    return {
        statusCode: 200,
        body: JSON.stringify(
          {
            message: event
          },
        ),
      };

}