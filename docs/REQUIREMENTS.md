# CoinGecko Engineering Written Assignment - Url Shortener
You are tasked to build a simple URL Shortener service as a microservice for a startup you recently joined.

A URL Shortener service, similar to [bit.ly](https://bitly.com/) and [tinyurl.com](https://tinyurl.com/) is a service that maps a short-form URL \(_"Short URL"_\) to a user-provided target URL \(_"Target URL"_\).

## Software Specifications

1. Your application is deployed with a web interface and a form field that accepts a Target URL.
1. When the Target URL is shortened, the user is returned with a **Short URL**, the original **Target URL** and the **Title** tag of the Target URL.
1. A Short URL can be publicly shared and accessed.
1. A Short URL path can be in any URI pattern, but should not exceed a maximum of 15 characters
1. Multiple Short URLs can share the same Target URL.
1. You need to produce a simple usage report for the application. This report should track the **number of clicks**, **originating geolocation** and **timestamp** of each visit to a Short URL.
1. You also need to publish a brief Wiki on your solution for short URL path. Explain the limitations and workarounds for your solution. 

## Scoring Guide
All submissions will be evaluated based on the following criteria:
- Completeness of solution including documentation and deployment
- Test coverage and overall approach to automated testing including unit tests and integration tests.
- Clean, understandable and proper version-control practices
- A comfortable UI/UX for end users


#### Extra Credit:
L3 and above candidates will additionally be evaluated based one or more of the following criteria:

- **Strategic design patterns** (e.g. [Service Objects](https://www.toptal.com/ruby-on-rails/rails-service-objects-tutorial), [Query Objects](https://martinfowler.com/eaaCatalog/queryObject.html), [Decorators](https://refactoring.guru/design-patterns/decorator))used in the solution to address extensibility, composability and other challenges.
- **Error and edge-case handling** beyond the user [happy path](http://xunitpatterns.com/happy%20path.html).
- **Scalability considerations** - what is the maximum number of short URLs or  supported concurrency of the application?
- **Security considerations** - is the solution susceptible to common web application vulnerabilities?
- Implementation of advanced, refactorable UI design components using popular frameworks.


## Submission Guide
- Your submission should include a **README** that includes at least an
    * installation guide
    * dependencies and other relevant information (such as scaffolding tools)
    * **deployed application URL**

- We do not expect candidates to take more than 2 weeks to complete the assignment. Most candidates are able to complete the assignment in half the allocated time.
- **Your submission should not aim to be exhaustive** - your submission should succinctly illustrate your depth and breadth of experience corresponding to the job level expectations for your application.
- Your submission should be **publicly accessible for read**
- Your submission will be used as a **foundation for the next/final round** of interview.
- You may use our [stackshare.io](https://stackshare.io/coingecko) profile as a point of reference.
