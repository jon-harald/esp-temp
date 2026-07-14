package no.brathen.esptemp.data.adafruit

import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.Path
import retrofit2.http.Query

/** Read-only Adafruit IO REST v2 (mirrors iOS AdafruitIOClient). */
interface AdafruitIoApi {
    @GET("api/v2/{username}/feeds/{feed}")
    suspend fun latest(
        @Path("username") username: String,
        @Path("feed") feed: String,
        @Header("X-AIO-Key") key: String,
    ): FeedDto

    @GET("api/v2/{username}/feeds/{feed}/data")
    suspend fun history(
        @Path("username") username: String,
        @Path("feed") feed: String,
        @Query("limit") limit: Int,
        @Header("X-AIO-Key") key: String,
    ): List<DataPointDto>
}
